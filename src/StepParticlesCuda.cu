#include "Particle.h"

#define NTHREADS 1024

static double *xPos, *yPos, *zPos, *xVel, *yVel, *zVel, *xAcc, *yAcc, *zAcc, *masses;
static unsigned int length;

__global__ void updateValuesKernel(
    double *xPos, double *yPos, double *zPos,
    double *xVel, double *yVel, double *zVel,
    double *xAcc, double *yAcc, double *zAcc,
    unsigned int length, double step) {

   unsigned int i = threadIdx.x + blockDim.x * blockIdx.x;

   if (i >= length) {
     return;
   }
    // Integrate with Symplectic euler.
    // Important to update velocity and use updated velocity to update position
    xVel[i] += step * xAcc[i];
    yVel[i] += step * yAcc[i];
    zVel[i] += step * zAcc[i];

    // Zero out acceleration now instead because of access patterns? 
    xAcc[i] = 0;
    yAcc[i] = 0;
    zAcc[i] = 0;

    xPos[i] += step * xVel[i];
    yPos[i] += step * yVel[i];
    zPos[i] += step * zVel[i];
}

__global__ void stepParticlesKernel(
    double *xPos, double *yPos, double *zPos,
    double *xAcc, double *yAcc, double *zAcc,
    double *masses,
    unsigned int length, double softening) {

   unsigned int i = threadIdx.x + blockDim.x * blockIdx.x;

   if (i >= length) {
      return;
   }

  for (unsigned int j = 0; j < length; ++j) {
      if (j == i) { continue;}

      // r_i_j is the distance vector
      //Vector3d r_i_j = particles[j]->getPosition() - particles[i]->getPosition();
      double r_i_j_x = xPos[j] - xPos[i];
      double r_i_j_y = yPos[j] - yPos[i];
      double r_i_j_z = zPos[j] - zPos[i];

      // bottom is scaling factor we divide by, we don't need to separate it out
      //double bottom = r_i_j.squaredNorm() + e2;
      double bottom = r_i_j_x * r_i_j_x + r_i_j_y * r_i_j_y + r_i_j_z * r_i_j_z + softening;

      bottom = sqrt(bottom * bottom * bottom); // bottom ^(3/2)

      //Vector3d f_i_j = r_i_j/ bottom;
      // Resuse r_i_j as f_i_j cause fuck it's verbose otherwise
      r_i_j_x /= bottom;
      r_i_j_y /= bottom;
      r_i_j_z /= bottom;

      // distvector = j pos - i pos
      // particles[i].acceleration accumlator = (m of j/ (dist^2 + e2)) * distvector

      // so f_i_j is the shared part of the calculation between the pair
      // which = distvector/(dist^2 + e2) but I multiply f_i_j by negative 1 to
      // reverse the direction so that it works for particle i too

      // Notice we are just adding to the accelerator
      //particles[i]->setAcceleration(particles[j]->getMass() * f_i_j + particles[i]->getAcceleration());
      //particles[j]->setAcceleration(particles[i]->getMass() * -1 * f_i_j + particles[j]->getAcceleration());
      xAcc[i] += masses[j] * r_i_j_x;
      yAcc[i] += masses[j] * r_i_j_y;
      zAcc[i] += masses[j] * r_i_j_z;
  }
}

void stepParticles(Particles &particles, double step, double softening) {
   dim3 dimBlock(NTHREADS, 1);
   dim3 dimGrid(length / NTHREADS + 1, 1);
   stepParticlesKernel<<<dimGrid, dimBlock>>>(
    xPos, yPos, zPos, xAcc, yAcc, zAcc, masses, length, softening);
   updateValuesKernel<<<dimGrid, dimBlock>>>(
    xPos, yPos, zPos, xVel, yVel, zVel, xAcc, yAcc, zAcc, length, step);

   cudaMemcpy(&particles.positions.xs[0], xPos, length * sizeof(double), cudaMemcpyDeviceToHost);
   cudaMemcpy(&particles.positions.ys[0], yPos, length * sizeof(double), cudaMemcpyDeviceToHost);
   cudaMemcpy(&particles.positions.zs[0], zPos, length * sizeof(double), cudaMemcpyDeviceToHost);
}

void init(Particles &particles, double step, double softening) {
   length = particles.length;

   cudaMalloc((void **)&xPos, length * sizeof(double));
   cudaMalloc((void **)&yPos, length * sizeof(double));
   cudaMalloc((void **)&zPos, length * sizeof(double));
   cudaMalloc((void **)&xVel, length * sizeof(double));
   cudaMalloc((void **)&yVel, length * sizeof(double));
   cudaMalloc((void **)&zVel, length * sizeof(double));
   cudaMalloc((void **)&xAcc, length * sizeof(double));
   cudaMalloc((void **)&yAcc, length * sizeof(double));
   cudaMalloc((void **)&zAcc, length * sizeof(double));
   cudaMalloc((void **)&masses, length * sizeof(double));

   cudaMemcpy(xPos, &particles.positions.xs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(yPos, &particles.positions.ys[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(zPos, &particles.positions.zs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(xVel, &particles.velocities.xs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(yVel, &particles.velocities.ys[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(zVel, &particles.velocities.zs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(xAcc, &particles.accelerations.xs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(yAcc, &particles.accelerations.ys[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(zAcc, &particles.accelerations.zs[0], length * sizeof(double), cudaMemcpyHostToDevice);
   cudaMemcpy(masses, &particles.mass[0], length * sizeof(double), cudaMemcpyHostToDevice);
}
