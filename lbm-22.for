C-----------------------------------------------------------------------
C     based on 2D python code by Jonas Latt Geneva University Coursera
C     code developed by Giles Richardson (GARCFD) in Cambridgeshire UK
C-----------------------------------------------------------------------
C     export NV_ACC_TIME=1
C     export ACC_NUM_CORES=8
C     export NVHPC_CUDA_HOME="/usr/local/cuda-12.1"
C
C     pgf77 -static-nvidia -acc=host      -o lbm-basic lbm-01.for
C     pgf77 -static-nvidia -acc=multicore -o lbm-mcore lbm-01.for
C     pgf77 -static-nvidia -acc -gpu=cc75 -o lbm-tesla lbm-01.for # Nvidia Tesla T4
C     pgf77 -static-nvidia -acc -gpu=cc86 -o lbm-tesla lbm-20.for # Nvidia A10
C-----------------------------------------------------------------------
      module allocated
        INTEGER,  ALLOCATABLE :: obs(:,:,:)
        INTEGER,  ALLOCATABLE :: cellnrm(:,:,:)
        INTEGER,  ALLOCATABLE :: nrm26(:)
        INTEGER,  ALLOCATABLE :: ref(:,:)

        REAL,     ALLOCATABLE :: vel(:,:,:,:)
        REAL,     ALLOCATABLE :: fin(:,:,:,:)
        REAL,     ALLOCATABLE :: fout(:,:,:,:)
        REAL,     ALLOCATABLE :: feq(:,:,:,:)
        REAL,     ALLOCATABLE :: rho(:,:,:)
        REAL,     ALLOCATABLE :: nut(:,:,:)
        REAL,     ALLOCATABLE :: nrm(:,:)
      end module allocated
C-----------------------------------------------------------------------

      program main
      use allocated
      implicit none

CCC   integer, parameter :: ndim=2, nvec=9
CCC   integer, parameter :: ndim=3, nvec=15, nrow=5, nvec0=26
      integer, parameter :: ndim=3, nvec=27, nrow=9, nvec0=26

      integer i,j,k,n,it,nits,nsav,nout,lcd,tang
      integer vec(nvec,ndim),col1(nrow),col2(nrow),col3(nrow)
      integer nexti,nextj,nextk,obsmax,nrmmax,inrm,v0,v0save
      integer im2,im1,ip1,ip2, jm2,jm1,jp1,jp2, km2,km1,kp1,kp2
      integer reflect

      real vec0(nvec0,ndim),smoo
      real Re,Lref,uLB,nuLB,omega,sum2,sum3,cu,usqr
      real cx,cy,cz,cr,xx,yy,zz,wt(nvec),vin(ndim)
      real smag,srinv,dx,dy,dz
      real dudx,dudy,dudz,dvdx,dvdy,dvdz,dwdx,dwdy,dwdz
      real dist,distmin,nrm1,nrm2,nrm3,rr2,rr3

C-----common
      integer ni,nj,nk,sa
      common  ni,nj,nk,sa

C-----read input file
      open(20,file="lbm-inputs.txt")
      read(20,*) ni,nj,nk  ! grid dimensions
      read(20,*) nsav      ! max saves
      read(20,*) nits      ! max iterations
      read(20,*) nout      ! write every nout
      read(20,*) tang      ! tangential on/off
      read(20,*) Re        ! Re
      read(20,*) Lref      ! Lref
      read(20,*) uLB       ! velocity in lattice units
      read(20,*) smag      ! smagorinsky constant
      close(20)

C-----constants
c     ni = 1000           ! lattice nodes
c     nj = 225            ! lattice nodes
c     nk = 400            ! lattice nodes
c     nits = 100          ! max iterations
      cx = real(ni)/4.0   ! sphere x-coord
      cy = real(nj)/2.0   ! sphere y-coord
      cz = real(nk)/2.0   ! sphere z-coord
      cr = real(nj)/5.0   ! sphere radius, in terms of nj dimension

      nuLB  = uLB*Lref/Re ! viscosity in lattice units
      omega = 1.0/(3.0*nuLB + 0.5) ! relaxation parameter
      vin = [uLB,0.0,0.0] ! inlet velocity

C-----write data to screen
      write(6,'(1X,A,3I5)')'ni nj nk  = ',ni,nj,nk
      write(6,'(1X,A,I10)')'mesh size = ',ni*nj*nk
      write(6,'(1X,A,I8)') 'nsav = ',nsav
      write(6,'(1X,A,I8)') 'nits = ',nits
      write(6,'(1X,A,I8)') 'nout = ',nout
      write(6,'(1X,A,I8)') 'tang = ',tang
      write(6,*) 'Re   = ',Re
      write(6,*) 'Lref = ',Lref
      write(6,*) 'uLB  = ',uLB
      write(6,*) 'nuLB = ',nuLB
      write(6,*) 'smag = ',smag
      write(6,*) 'omega = ',omega

C=====allocate
      ALLOCATE( obs(ni,nj,nk) )       ! int
      ALLOCATE(cellnrm(ni,nj,nk) )    ! int
      ALLOCATE( vel(ni,nj,nk,ndim) )  ! real
      ALLOCATE( fin(ni,nj,nk,nvec) )  ! real
      ALLOCATE(fout(ni,nj,nk,nvec) )  ! real
      ALLOCATE( feq(ni,nj,nk,nvec) )  ! real
      ALLOCATE( rho(ni,nj,nk) )       ! real
      ALLOCATE( nut(ni,nj,nk) )       ! real

C=====initialise vec vectors
      vec(1, :) = (/ 1,-1,-1 /) ! r3
      vec(2, :) = (/ 1,-1, 0 /)
      vec(3, :) = (/ 1,-1, 1 /) ! r3
      vec(4, :) = (/ 1, 0,-1 /) 
      vec(5, :) = (/ 1, 0, 0 /) ! x+
      vec(6, :) = (/ 1, 0, 1 /) 
      vec(7, :) = (/ 1, 1,-1 /) ! r3
      vec(8, :) = (/ 1, 1, 0 /)  
      vec(9, :) = (/ 1, 1, 1 /) ! r3

      vec(10,:) = (/ 0,-1,-1 /)
      vec(11,:) = (/ 0,-1, 0 /) ! y-
      vec(12,:) = (/ 0,-1, 1 /)
      vec(13,:) = (/ 0, 0,-1 /) ! z-
      vec(14,:) = (/ 0, 0, 0 /) 
      vec(15,:) = (/ 0, 0, 1 /) ! z+
      vec(16,:) = (/ 0, 1,-1 /)
      vec(17,:) = (/ 0, 1, 0 /) ! y+
      vec(18,:) = (/ 0, 1, 1 /)

      vec(19,:) = (/-1,-1,-1 /) ! r3
      vec(20,:) = (/-1,-1, 0 /)
      vec(21,:) = (/-1,-1, 1 /) ! r3
      vec(22,:) = (/-1, 0,-1 /) 
      vec(23,:) = (/-1, 0, 0 /) ! x-
      vec(24,:) = (/-1, 0, 1 /)
      vec(25,:) = (/-1, 1,-1 /) ! r3
      vec(26,:) = (/-1, 1, 0 /)
      vec(27,:) = (/-1, 1, 1 /) ! r3

      rr2 = 0.707 ! 1/sqrt(2)
      rr3 = 0.577 ! 1/sqrt(3)

C=====initialise vec0 vectors
      vec0(1, :) = (/  1.0,  0.0,  0.0 /) ! 6 main axes
      vec0(2, :) = (/ -1.0,  0.0,  0.0 /)
      vec0(3, :) = (/  0.0,  1.0,  0.0 /)
      vec0(4, :) = (/  0.0, -1.0,  0.0 /)
      vec0(5, :) = (/  0.0,  0.0,  1.0 /) 
      vec0(6, :) = (/  0.0,  0.0, -1.0 /) 

      vec0(7, :) = (/  rr2,  rr2,  0.0 /) ! 12 in-plane diagonals
      vec0(8, :) = (/  rr2, -rr2,  0.0 /)
      vec0(9, :) = (/ -rr2,  rr2,  0.0 /)
      vec0(10,:) = (/ -rr2, -rr2,  0.0 /)
      vec0(11,:) = (/  rr2,  0.0,  rr2 /)
      vec0(12,:) = (/  rr2,  0.0, -rr2 /)
      vec0(13,:) = (/ -rr2,  0.0,  rr2 /)
      vec0(14,:) = (/ -rr2,  0.0, -rr2 /)
      vec0(15,:) = (/  0.0,  rr2,  rr2 /)
      vec0(16,:) = (/  0.0,  rr2, -rr2 /)
      vec0(17,:) = (/  0.0, -rr2,  rr2 /)
      vec0(18,:) = (/  0.0, -rr2, -rr2 /)

      vec0(19,:) = (/  rr3,  rr3,  rr3 /) ! 8 out-of-plane diagonals
      vec0(20,:) = (/ -rr3,  rr3,  rr3 /)
      vec0(21,:) = (/  rr3, -rr3,  rr3 /) 
      vec0(22,:) = (/ -rr3, -rr3,  rr3 /) 
      vec0(23,:) = (/  rr3,  rr3, -rr3 /)
      vec0(24,:) = (/ -rr3,  rr3, -rr3 /)
      vec0(25,:) = (/  rr3, -rr3, -rr3 /)
      vec0(26,:) = (/ -rr3, -rr3, -rr3 /)
 
C=====initialise weights
      wt(1)  = 1.0 / 216.0 ! r3
      wt(2)  = 1.0 /  54.0 ! r2
      wt(3)  = 1.0 / 216.0 ! r3
      wt(4)  = 1.0 /  54.0 ! r2
      wt(5)  = 2.0 /  27.0 ! x++
      wt(6)  = 1.0 /  54.0 ! r2
      wt(7)  = 1.0 / 216.0 ! r3
      wt(8)  = 1.0 /  54.0 ! r2
      wt(9)  = 1.0 / 216.0 ! r3

      wt(10) = 1.0 /  54.0 ! r2
      wt(11) = 2.0 /  27.0 ! y--
      wt(12) = 1.0 /  54.0 ! r2
      wt(13) = 2.0 /  27.0 ! z--
      wt(14) = 8.0 /  27.0 ! centre
      wt(15) = 2.0 /  27.0 ! z++
      wt(16) = 1.0 /  54.0 ! r2
      wt(17) = 2.0 /  27.0 ! y++
      wt(18) = 1.0 /  54.0 ! r2

      wt(19) = 1.0 / 216.0 ! r3
      wt(20) = 1.0 /  54.0 ! r2
      wt(21) = 1.0 / 216.0 ! r3
      wt(22) = 1.0 /  54.0 ! r2
      wt(23) = 2.0 /  27.0 ! x--
      wt(24) = 1.0 /  54.0 ! r2
      wt(25) = 1.0 / 216.0 ! r3
      wt(26) = 1.0 /  54.0 ! r2
      wt(27) = 1.0 / 216.0 ! r3

      col1 = (/ 1, 2, 3, 4, 5, 6, 7, 8, 9  /)
      col2 = (/ 10,11,12,13,14,15,16,17,18 /)
      col3 = (/ 19,20,21,22,23,24,25,26,27 /)

      obs = 1     ! int array (default = 1)
      cellnrm = 0 ! int array (default = 0)
      fin = 0.0   ! real array
      fout= 0.0   ! real array
      feq = 0.0   ! real array
      rho = 0.0   ! real array
      vel = 0.0   ! real array
      nut = 0.0   ! real array


C-----original sphere geometry
      if (.false.) then       
      do i = 1,ni
      do j = 1,nj
      do k = 1,nk
        xx = real(i-1) + 0.5
        yy = real(j-1) + 0.5
        zz = real(k-1) + 0.5
        dx = xx-cx
        dy = yy-cy
        dz = 0.0 ! dz = zz-cz
        if ((dx*dx + dy*dy + dz*dz) .LT. (cr*cr)) then
          obs(i,j,k) = 1
        endif
      enddo
      enddo
      enddo
      endif


C-----set walls (if not periodic)
      if (.false.) then
      do i = 1,ni
        do k = 1,nk
          obs(i, 1,k) = 1 ! ymin
          obs(i,nj,k) = 1 ! ymax
        enddo
        do j = 1,nj ! side walls
          obs(i,j, 1) = 1 ! zmin
          obs(i,j,nk) = 1 ! zmax
        enddo
      enddo
      endif


C-----read obstacle.dat file from ufocfd
C-----read  normals.dat file from ufocfd
      if (.true.) then
        write(6,*) "read obstacle.dat and normals.dat"
        open(20,file="obstacle.dat")
        open(30,file="normals.dat")

        read(20,*) ! im jm km header
        read(20,*) obsmax
        read(30,*) nrmmax

        allocate( nrm(nrmmax,ndim) )
        allocate( ref(nvec0, nvec) )
        allocate( nrm26(nrmmax) )

        nrm(:,:) = 0.0
        ref(:,:) = 0
        nrm26(:) = 0

        inrm = 0

        do n = 1,obsmax

          read(20,*) lcd,i,j,k
          obs(i,j,k) = lcd ! (0 or -1)

          if (lcd.eq.0) then ! cutc
            inrm = inrm + 1
            cellnrm(i,j,k) = inrm
            read(30,*) nrm1,nrm2,nrm3
            nrm(inrm,1) = nrm1
            nrm(inrm,2) = nrm2
            nrm(inrm,3) = nrm3
          endif

        enddo

        close(20)
        close(30)

        write(6,*)"obsmax = ", obsmax
        write(6,*)"nrmmax = ", nrmmax
        write(6,*)"inrm =   ", inrm
        write(6,*)"done"
      endif


C=====convert simplify nrm(n,:) array to nrm26() array
      do n = 1,nrmmax

        nrm1 = nrm(n,1)
        nrm2 = nrm(n,2)
        nrm3 = nrm(n,3)
 
        distmin = 10.0

        do v0 = 1,nvec0

            dx = nrm1 - vec0(v0,1) 
            dy = nrm2 - vec0(v0,2) 
            dz = nrm3 - vec0(v0,3) 
            dist = sqrt(dx*dx + dy*dy + dz*dz)

            if (dist.lt.distmin) then
              v0save  = v0
              distmin = dist 
            endif

        enddo  

        nrm26(n) = v0save

      enddo




C=====specify the reflection matrix

      ref(1, :)=(/ 15, 2, 3, 9, 10, 11, 12, 8, 4, 5, 6, 7, 13, 14, 1 /)
      ref(2, :)=(/ 15, 2, 3, 9, 10, 11, 12, 8, 4, 5, 6, 7, 13, 14, 1 /)
      ref(3, :)=(/ 1, 14, 3, 6, 7, 4, 5, 8, 11, 12, 9, 10, 13, 2, 15 /)
      ref(4, :)=(/ 1, 14, 3, 6, 7, 4, 5, 8, 11, 12, 9, 10, 13, 2, 15 /)
      ref(5, :)=(/ 1, 2, 13, 5, 4, 7, 6, 8, 10, 9, 12, 11, 3, 14, 15 /)
      ref(6, :)=(/ 1, 2, 13, 5, 4, 7, 6, 8, 10, 9, 12, 11, 3, 14, 15 /)
      ref(7, :)=(/ 14, 15, 3, 11, 12, 6, 7, 8, 9, 10, 4, 5, 13, 1, 2 /)
      ref(8, :)=(/ 2, 1, 3, 4, 5, 9, 10, 8, 6, 7, 11, 12, 13, 15, 14 /)
      ref(9, :)=(/ 2, 1, 3, 4, 5, 9, 10, 8, 6, 7, 11, 12, 13, 15, 14 /)
      ref(10,:)=(/ 14, 15, 3, 11, 12, 6, 7, 8, 9, 10, 4, 5, 13, 1, 2 /)
      ref(11,:)=(/ 13, 2, 15, 10, 5, 12, 7, 8, 9, 4, 11, 6, 1, 14, 3 /)
      ref(12,:)=(/ 3, 2, 1, 4, 9, 6, 11, 8, 5, 10, 7, 12, 15, 14, 13 /)
      ref(13,:)=(/ 3, 2, 1, 4, 9, 6, 11, 8, 5, 10, 7, 12, 15, 14, 13 /)
      ref(14,:)=(/ 13, 2, 15, 10, 5, 12, 7, 8, 9, 4, 11, 6, 1, 14, 3 /)
      ref(15,:)=(/ 1, 13, 14, 7, 5, 6, 4, 8, 12, 10, 11, 9, 2, 3, 15 /)
      ref(16,:)=(/ 1, 3, 2, 4, 6, 5, 7, 8, 9, 11, 10, 12, 14, 13, 15 /)
      ref(17,:)=(/ 1, 3, 2, 4, 6, 5, 7, 8, 9, 11, 10, 12, 14, 13, 15 /)
      ref(18,:)=(/ 1, 13, 14, 7, 5, 6, 4, 8, 12, 10, 11, 9, 2, 3, 15 /)
      ref(19,:)=(/ 7, 10, 11, 12, 13, 14, 1, 8, 15, 2, 3, 4, 5, 6, 9 /)
      ref(20,:)=(/ 4, 5, 6, 1, 2, 3, 9, 8, 7, 13, 14, 15, 10, 11, 12 /)
      ref(21,:)=(/ 5, 4, 9, 2, 1, 10, 13, 8, 3, 6, 15, 14, 7, 12, 11 /)
      ref(22,:)=(/ 6, 9, 4, 3, 11, 1, 14, 8, 2, 15, 5, 13, 12, 7, 10 /)
      ref(23,:)=(/ 6, 9, 4, 3, 11, 1, 14, 8, 2, 15, 5, 13, 12, 7, 10 /)
      ref(24,:)=(/ 5, 4, 9, 2, 1, 10, 13, 8, 3, 6, 15, 14, 7, 12, 11 /)
      ref(25,:)=(/ 4, 5, 6, 1, 2, 3, 9, 8, 7, 13, 14, 15, 10, 11, 12 /)
      ref(26,:)=(/ 7, 10, 11, 12, 13, 14, 1, 8, 15, 2, 3, 4, 5, 6, 9 /)






C=====initial velocity field
      write(6,*)"initial velocity"
      do i = 1,ni
      do j = 1,nj
      do k = 1,nk

        if (obs(i,j,k).eq.1) then ! fluid
          vel(i,j,k,1) = vin(1)
          vel(i,j,k,2) = vin(2)
          vel(i,j,k,3) = vin(3)
        endif

        if (obs(i,j,k).le.0) then ! cutcell or solid
          vel(i,j,k,1) = 0.0
          vel(i,j,k,2) = 0.0
          vel(i,j,k,3) = 0.0
        endif

      enddo
      enddo
      enddo


C=====equilibrium distribution function
C-----fin = equilibrium(1,u)
      do k = 1,nk
      do j = 1,nj
      do i = 1,ni

        usqr = vel(i,j,k,1)**2 + vel(i,j,k,2)**2 + vel(i,j,k,3)**2
        do n = 1,nvec
          cu = vec(n,1)*vel(i,j,k,1)
     &       + vec(n,2)*vel(i,j,k,2)
     &       + vec(n,3)*vel(i,j,k,3)
C-----------------------(rho=1)
          fin(i,j,k,n) = 1.0*wt(n)*(1 + 3*cu + 4.5*cu**2 - 1.5*usqr)
        enddo

      enddo
      enddo
      enddo

      write(6,*)"start iterations"


C=====saving vtk files
      do sa = 1, nsav

!$acc data copy(obs,vel,fin,fout,feq,rho)
!$acc data copy(vec,wt,col1,col2,col3,vin)
!$acc data copy(nut,cellnrm,nrm26,ref)

C=====main iterations
      do it = 1, nits

!$acc kernels loop independent
      do k = 1,nk
!$acc loop independent
      do j = 1,nj
!$acc loop independent
      do i = 1,ni

C     STEP1 - right wall outflow condition
      if (i.eq.ni) then
         do n = 1,nrow
           fin(ni,j,k,col3(n)) = fin(ni-1,j,k,col3(n))
         enddo
      endif

      rho(i,j,k) = 0.0
      vel(i,j,k,:) = 0.0

C     STEP2 - compute macroscopic variables rho and u
      do n = 1,nvec
        rho(i,j,k) = rho(i,j,k) + fin(i,j,k,n)
        vel(i,j,k,1) = vel(i,j,k,1) + vec(n,1) * fin(i,j,k,n)
        vel(i,j,k,2) = vel(i,j,k,2) + vec(n,2) * fin(i,j,k,n)
        vel(i,j,k,3) = vel(i,j,k,3) + vec(n,3) * fin(i,j,k,n)
      enddo
      
      vel(i,j,k,1) = vel(i,j,k,1) / rho(i,j,k)
      vel(i,j,k,2) = vel(i,j,k,2) / rho(i,j,k)
      vel(i,j,k,3) = vel(i,j,k,3) / rho(i,j,k)

C     STEP3 - left wall ! (and upper/lower wall) inflow condition
      if (i.eq.1) then  ! .or.(j.eq.1).or.(j.eq.nj)) then
        vel(1,j,k,1) = vin(1)
        vel(1,j,k,2) = vin(2)
        vel(1,j,k,3) = vin(3)
        sum2 = 0.0
        sum3 = 0.0
        do n = 1,nrow
          sum2 = sum2 + fin(1,j,k,col2(n))
          sum3 = sum3 + fin(1,j,k,col3(n))
          rho(1,j,k) = (sum2 + 2.0*sum3) / (1.0-vel(1,j,k,1))
        enddo
      endif

C     STEP4 - compute equilibrium (rho, vel)
        usqr = vel(i,j,k,1)**2 + vel(i,j,k,2)**2 + vel(i,j,k,3)**2
        do n = 1,nvec
          cu = vec(n,1)*vel(i,j,k,1)
     &       + vec(n,2)*vel(i,j,k,2)
     &       + vec(n,3)*vel(i,j,k,3)
          feq(i,j,k,n) = rho(i,j,k)*wt(n)*
     &    (1.0 + 3.0*cu + 4.5*cu**2.0 - 1.5*usqr)
        enddo

C     STEP5 - calculate populations (at inlet)       
      if (i.eq.1) then
        do n = 1,nrow
          fin(1,j,k,col1(n)) = feq(1,j,k,col1(n))
     &                       + fin(1,j,k,col3(nrow+1-n))
     &                       - feq(1,j,k,col3(nrow+1-n))
        enddo
      endif

      omega = 1.0/(3.0*(nuLB+nut(i,j,k)) + 0.5) ! relaxation parameter

C     STEP6 - collision step
      do n = 1,nvec
        fout(i,j,k,n) = fin(i,j,k,n)
     &         - omega*(fin(i,j,k,n) - feq(i,j,k,n))
      enddo

C     STEP7 - obstacle wall condition
      if (obs(i,j,k).eq.0) then ! cutcell

        if (tang.eq.0) then ! no-slip bounce
          do n = 1,nvec
            fout(i,j,k,n) = fin(i,j,k,nvec+1-n)
          enddo
        endif

        if (tang.eq.1) then ! free-slip reflection
          do n = 1,nvec
            reflect = ref( nrm26( cellnrm(i,j,k) ) ,n)
            fout(i,j,k,reflect) = fin(i,j,k,n)
          enddo
        endif

      endif

      enddo
      enddo
      enddo

!$acc kernels loop independent
      do k = 1,nk
!$acc loop independent
      do j = 1,nj
!$acc loop independent
      do i = 1,ni


C     calc smagorinsky turbulence
      if (smag .gt. 0.0) then

        im2 = i-2; im1 = i-1; ip1 = i+1; ip2 = i+2 
        jm2 = j-2; jm1 = j-1; jp1 = j+1; jp2 = j+2 
        km2 = k-2; km1 = k-1; kp1 = k+1; kp2 = k+2 

        if (i.lt.3) then
          im2 = 1; im1 = 2; ip1 = 4; ip2 = 5  
        endif
        if (j.lt.3) then
          jm2 = 1; jm1 = 2; jp1 = 4; jp2 = 5
        endif
        if (k.lt.3) then
          km2 = 1; km1 = 2; kp1 = 4; kp2 = 5
        endif
        if (i.gt.ni-2) then
          im2 = ni-4; im1 = ni-3; ip1 = ni-1; ip2 = ni
        endif
        if (j.gt.nj-2) then
          jm2 = nj-4; jm1 = nj-3; jp1 = nj-1; jp2 = nj
        endif
        if (k.gt.nk-2) then
          km2 = nk-4; km1 = nk-3; kp1 = nk-1; kp2 = nk
        endif

        if (.false.) then
        dudx = (vel(im1,j,k,1) - vel(im2,j,k,1)
     &       +  vel(ip2,j,k,1) - vel(ip1,j,k,1) / 2.0)
        dudy = (vel(i,jm1,k,1) - vel(i,jm2,k,1)
     &       +  vel(i,jp2,k,1) - vel(i,jp1,k,1) / 2.0)
        dudz = (vel(i,j,km1,1) - vel(i,j,km2,1)
     &       +  vel(i,j,kp2,1) - vel(i,j,kp1,1) / 2.0)

        dvdx = (vel(im1,j,k,2) - vel(im2,j,k,2)
     &       +  vel(ip2,j,k,2) - vel(ip1,j,k,2) / 2.0)
        dvdy = (vel(i,jm1,k,2) - vel(i,jm2,k,2)
     &       +  vel(i,jp2,k,2) - vel(i,jp1,k,2) / 2.0)
        dvdz = (vel(i,j,km1,2) - vel(i,j,km2,2)
     &       +  vel(i,j,kp2,2) - vel(i,j,kp1,2) / 2.0)

        dwdx = (vel(im1,j,k,3) - vel(im2,j,k,3)
     &       +  vel(ip2,j,k,3) - vel(ip1,j,k,3) / 2.0)
        dwdy = (vel(i,jm1,k,3) - vel(i,jm2,k,3)
     &       +  vel(i,jp2,k,3) - vel(i,jp1,k,3) / 2.0)
        dwdz = (vel(i,j,km1,3) - vel(i,j,km2,3)
     &       +  vel(i,j,kp2,3) - vel(i,j,kp1,3) / 2.0)
        endif

        if (.true.) then
        dudx = (vel(im2,j,k,1) - 8*vel(im1,j,k,1)
     &      + 8*vel(ip1,j,k,1) -   vel(ip2,j,k,1) / 12.0)
        dudy = (vel(i,jm2,k,1) - 8*vel(i,jm1,k,1)
     &      + 8*vel(i,jp1,k,1) -   vel(i,jp2,k,1) / 12.0)
        dudz = (vel(i,j,km2,1) - 8*vel(i,j,km1,1)
     &      + 8*vel(i,j,kp1,1) -   vel(i,j,kp2,1) / 12.0)

        dvdx = (vel(im2,j,k,2) - 8*vel(im1,j,k,2)
     &      + 8*vel(ip1,j,k,2) -   vel(ip2,j,k,2) / 12.0)
        dvdy = (vel(i,jm2,k,2) - 8*vel(i,jm1,k,2)
     &      + 8*vel(i,jp1,k,2) -   vel(i,jp2,k,2) / 12.0)
        dvdz = (vel(i,j,km2,2) - 8*vel(i,j,km1,2)
     &      + 8*vel(i,j,kp1,2) -   vel(i,j,kp2,2) / 12.0)

        dwdx = (vel(im2,j,k,3) - 8*vel(im1,j,k,3)
     &      + 8*vel(ip1,j,k,3) -   vel(ip2,j,k,3) / 12.0)
        dwdy = (vel(i,jm2,k,3) - 8*vel(i,jm1,k,3)
     &      + 8*vel(i,jp1,k,3) -   vel(i,jp2,k,3) / 12.0)
        dwdz = (vel(i,j,km2,3) - 8*vel(i,j,km1,3)
     &      + 8*vel(i,j,kp1,3) -   vel(i,j,kp2,3) / 12.0)
        endif

        srinv = sqrt( 2.0*dudx*dudx + 2.0*dvdy*dvdy + 2.0*dwdz*dwdz +
     &    (dudz+dwdx)**2.0 + (dudy+dvdx)**2.0 + (dwdy+dvdz)**2.0 )

      else
        srinv = 0.0
      endif

      smoo = max (0.0,real(11-i)*0.05)
      smoo = 0.0
      nut(i,j,k) = (smag+smoo)*(smag+smoo)*srinv


C     STEP8 - streaming step
        do n = 1,nvec

          nexti = i + vec(n,1)
          nextj = j + vec(n,2)
          nextk = k + vec(n,3)

C---------periodic boundaries
          if (.true.) then
            if (nexti.lt.1)  nexti = ni
            if (nextj.lt.1)  nextj = nj
            if (nextk.lt.1)  nextk = nk
            if (nexti.gt.ni) nexti = 1
            if (nextj.gt.nj) nextj = 1
            if (nextk.gt.nk) nextk = 1
          endif
          
          if ( obs(nexti,nextj,nextk).ge.0 ) then          
            fin(nexti,nextj,nextk,n) = fout(i,j,k,n)
          endif

        enddo

      enddo
      enddo
      enddo

C-----write monitor
      if (mod(it,nout).eq.0) then
        write(6,10)" sa = ",sa," it = ",it," vx = ",
     &  vel(int(1.0*ni),int(0.5*nj),int(0.5*nk),1)
      endif

      enddo ! nits

!$acc end data
!$acc end data
!$acc end data

      call write_vxmax()
      call write_binary_vtk()

      enddo ! nsav
C=====end main iteration loop


   10 format(A,I3,A,I6,A,F8.4)

      end ! main
C===============




      subroutine write_vxmax()
      use allocated
      implicit none

      integer i,j,k,ii,jj,kk
      real vxmag,vxmax
      integer ni,nj,nk
      common  ni,nj,nk

C-----calc max velocity
      vxmax = 0.0
      do k = 1,nk
      do j = 1,nj
      do i = 1,ni

        vxmag = vel(i,j,k,1)
        if (vxmag.gt.vxmax) then
          vxmax = vxmag
          ii = i
          jj = j
          kk = k
        endif

      enddo
      enddo
      enddo
      write(6,*) "vxmax = ",vxmax," at ",ii,jj,kk

      end




      subroutine write_ascii_vtk()
      use allocated
      implicit none

      integer i,j,k
      integer ni,nj,nk,sa
      common  ni,nj,nk,sa

C-----start ascii VTK file
      write(6,*)"write ascii vtk file"
      OPEN(unit=20,file='lbm.vtk')
      write(20,10)'# vtk DataFile Version 3.0'
      write(20,10)'vtk output'
      write(20,10)'ASCII'
      write(20,10)'DATASET RECTILINEAR_GRID'
      write(20,20)'DIMENSIONS ',ni+1,nj+1,nk+1
      write(20,30)'X_COORDINATES ',ni+1,' float'
      write(20,*)   (real(i-1),i=1,ni+1)
      write(20,30)'Y_COORDINATES ',nj+1,' float'
      write(20,*)   (real(j-1),j=1,nj+1)
      write(20,30)'Z_COORDINATES ',nk+1,' float'
      write(20,*)   (real(k-1),k=1,nk+1)
      write(20,40)'CELL_DATA ',ni*nj*nk
C-----obs
      write(20,10)'SCALARS obs int'
      write(20,10)'LOOKUP_TABLE default'
      write(20,*)(((obs(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----rho
      write(20,10)'SCALARS rho float'
      write(20,10)'LOOKUP_TABLE default'
      write(20,*)(((rho(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----nut
      write(20,10)'SCALARS nut float'
      write(20,10)'LOOKUP_TABLE default'
      write(20,*)(((nut(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----vel
      write(20,10)'VECTORS vel float'
      write(20,*)(((vel(i,j,k,1),vel(i,j,k,2),vel(i,j,k,3),
     &                           i=1,ni),j=1,nj),k=1,nk)
      close(20)

   10 format(A)
   20 format(A,3I4)
   30 format(A,I3,A)
   40 format(A,I9)

      end



C-----write binary VTK file
      subroutine write_binary_vtk()

      use allocated
      implicit none

      integer i,j,k
      integer ni,nj,nk,sa
      common  ni,nj,nk,sa

      CHARACTER(10) outfile
      CHARACTER(3)  string
      CHARACTER(LEN=1)  :: lf
      CHARACTER(LEN=10) :: str1,str2,str3,str4
      lf = char(10)

      write(6,*)"write binary VTK"

C-----output filename
      write(unit=string, fmt='(I3.3)') sa
      outfile = 'lbm'//string//'.vtk'
      write(6,*)"outfile = ",outfile

!$acc data copy(obs,vel,rho,nut)

      OPEN(unit=20, file=outfile, form='unformatted',
     &    access='stream',status='replace',convert="big_endian")
      write(20)'# vtk DataFile Version 3.0'//lf
      write(20)'vtk output'//lf
      write(20)'BINARY'//lf
      write(20)'DATASET RECTILINEAR_GRID'//lf
      write(str1(1:10),'(i10)') ni+1
      write(str2(1:10),'(i10)') nj+1
      write(str3(1:10),'(i10)') nk+1
      write(str4(1:10),'(i10)') ni*nj*nk
      write(20)'DIMENSIONS '//str1//str2//str3//lf
      write(20)'X_COORDINATES '//str1//' float'//lf
      write(20)(real(i-1),i=1,ni+1)
      write(20)'Y_COORDINATES '//str2//' float'//lf
      write(20)(real(j-1),j=1,nj+1)
      write(20)'Z_COORDINATES '//str3//' float'//lf
      write(20)(real(k-1),k=1,nk+1)
      write(20)'CELL_DATA '//str4//lf
C-----obs
      write(20)'SCALARS obs int'//lf
      write(20)'LOOKUP_TABLE default'//lf
      write(20)(((obs(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----rho
      write(20)'SCALARS rho float'//lf
      write(20)'LOOKUP_TABLE default'//lf
      write(20)(((rho(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----nut
      write(20)'SCALARS nut float'//lf
      write(20)'LOOKUP_TABLE default'//lf
      write(20)(((nut(i,j,k),i=1,ni),j=1,nj),k=1,nk)
C-----vel
      write(20)'VECTORS vel float'//lf
      write(20)(((vel(i,j,k,1),vel(i,j,k,2),vel(i,j,k,3),
     &             i=1,ni),j=1,nj),k=1,nk)
      close(20)

!$acc end data

      end




