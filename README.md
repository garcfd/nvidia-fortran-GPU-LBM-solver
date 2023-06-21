# nvidia-fortran-GPU-LBM-solver
nvidia pgf77 fortran openacc gpu solver

The main program you want to use is the lbm-18.for, which is the 
Lattice Bolzmann solver. The compiler commands are included in the 
"compile" file, which makes 3 executable files. You will obviously
need a Telsa GPU if you want to run the GPU version, but the other
2 versions (basic and multicore) will run fine on just CPU. There 
are also some instructions on what you need to download and install 
to get nvidia (free of charge) installed on your machine. 

This method used obstacle.dat and normals.dat which come from ufo-cfd.
Obstacle.dat is the locations of all the obstacle points in i,j,k locations,
whwich also specifies if they are cut-cells or dead cells, like in ufo-cfd.
Normals.dat is the surface normals of all the surface (cut-cell) points.

The LBM code then changes the surface normals into pre-defined normals,
(there are 26 of them) which simplifies the surface normal representation.
These surface normals are then linked with their reflection vectors for 
all lattice vectors. So this is an array of 26x15 reflections which have
been pre calculated.

There is also porsche.stl file used to create the obstacle file.
https://drive.google.com/file/d/1_Z8FRGjBYJTyB6_KUXJ2Iy8ZvH4JUBLG

