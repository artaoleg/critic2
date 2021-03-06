!> Part of the following code has been adapted from the elk distribution, 
!> version 1.3.2.
!> Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
!> Distributed under the terms of the GNU General Public License.

! J.L. Casals Sainz contributed the adaptation to elk 2.1.25

! Copyright (c) 2015 Alberto Otero de la Roza <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>. 
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or (at
! your option) any later version.
! 
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
! 
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

!> Interface to ELK densities.
module elk_private
  implicit none

  private

  type elkwfn
     real*8 :: x2c(3,3)
     real*8 :: c2x(3,3)
     integer :: lmaxvr
     real*8, allocatable :: spr(:,:)
     real*8, allocatable :: spr_a(:)
     real*8, allocatable :: spr_b(:)
     integer, allocatable :: nrmt(:)
     integer :: ngvec
     real*8, allocatable :: vgc(:,:) 
     integer, allocatable :: igfft(:)
     integer :: ncel0
     real*8, allocatable :: xcel(:,:)
     integer, allocatable :: iesp(:)
     real*8, allocatable :: rhomt(:,:,:)
     complex*16, allocatable :: rhok(:)
     real*8, allocatable :: rmt(:)
     integer :: n(3)
   contains
     procedure :: end => elkwfn_end !< Deallocate all data
     procedure :: rmt_atom !< RMT from the closest atom
     procedure :: read_out !< Read the elkwfn data from an elk's OUT file
     procedure :: rho2 !< Calculate the density and derivatives at a point
     procedure :: tolap !< Convert an elkwfn into its Laplacian
  end type elkwfn
  public :: elkwfn

  private :: elk_geometry
  private :: read_elk_state
  private :: read_elk_myout
  private :: sortidx
  private :: local_nearest_atom

  ! private to the module
  integer, parameter :: matom = 100

contains

  subroutine elkwfn_end(f)
    class(elkwfn), intent(inout) :: f

    if (allocated(f%spr)) deallocate(f%spr)
    if (allocated(f%spr_a)) deallocate(f%spr_a)
    if (allocated(f%spr_b)) deallocate(f%spr_b)
    if (allocated(f%nrmt)) deallocate(f%nrmt)
    if (allocated(f%vgc)) deallocate(f%vgc)
    if (allocated(f%igfft)) deallocate(f%igfft)
    if (allocated(f%xcel)) deallocate(f%xcel)
    if (allocated(f%iesp)) deallocate(f%iesp)
    if (allocated(f%rhomt)) deallocate(f%rhomt)
    if (allocated(f%rhok)) deallocate(f%rhok)
    if (allocated(f%rmt)) deallocate(f%rmt)

  end subroutine elkwfn_end

  !> Return the rmt for the atom at position x
  function rmt_atom(f,x)
    class(elkwfn), intent(in) :: f
    real*8, intent(in) :: x(3)
    real*8 :: rmt_atom

    integer :: nid
    real*8 :: dist
    integer :: lvec(3)

    call local_nearest_atom(f,x,nid,dist,lvec)
    rmt_atom = f%rmt(f%iesp(nid))
    
  end function rmt_atom

  !> Read a elkwfn scalar field from an OUT file 
  subroutine read_out(f,file,file2,file3)
    class(elkwfn), intent(inout) :: f
    character*(*), intent(in) :: file, file2
    character*(*), intent(in), optional :: file3
    
    call f%end()

    ! geometry data
    call elk_geometry(f,file2)

    ! state data
    call read_elk_state(f,file)

    ! read the third file
    if (present(file3)) then
       call read_elk_myout(f,file3)
    end if

  end subroutine read_out

  ! The following code has been adapted from the elk distribution,
  ! version 1.3.2 Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma
  ! and C. Ambrosch-Draxl.  This file is distributed under the terms
  ! of the GNU General Public License.
  subroutine elk_geometry(f,filename)
    use tools_io, only: fopen_read, getline_raw, equal, getword, ferror, faterr, zatguess,&
       fclose
    use tools_math, only: matinv
    class(elkwfn), intent(inout) :: f
    character*(*), intent(in) :: filename

    character(len=:), allocatable :: line, atname
    integer :: lu, i, zat, nat, j, lp
    integer, allocatable :: natoms(:)
    integer :: nspecies
    real*8, allocatable :: aux(:,:)
    logical :: ok

    lu = fopen_read(filename)
    ! ignore the 'scale' stuff
    do i = 1, 14
       read(lu,*)
    end do

    read(lu,'(3G18.10)') f%x2c(:,1)
    read(lu,'(3G18.10)') f%x2c(:,2)
    read(lu,'(3G18.10)') f%x2c(:,3)
    f%c2x = matinv(f%x2c)

    ok = getline_raw(lu,line,.true.)
    ok = getline_raw(lu,line,.true.)
    if (equal(line,'molecule')) call ferror('read_elk_geometry','Isolated molecules not supported',faterr,line)

    f%ncel0 = 0
    if (allocated(f%xcel)) deallocate(f%xcel)
    allocate(f%xcel(3,matom))
    read(lu,'(I4)') nspecies
    if (allocated(natoms)) deallocate(natoms)
    allocate(natoms(nspecies))
    do i = 1, nspecies
       ok = getline_raw(lu,line,.true.)
       lp = 1
       atname = getword(line,lp)
       do j = 1, len(atname)
          if (atname(j:j) == "'") atname(j:j) = " "
          if (atname(j:j) == '"') atname(j:j) = " "
       end do
       zat = zatguess(atname)
       if (zat == -1) call ferror('read_elk_geometry','Species file name must start with an atomic symbol',faterr)
       read(lu,*) natoms(i)
       do j = 1, natoms(i)
          f%ncel0 = f%ncel0 + 1
          if (f%ncel0 > size(f%xcel,2)) then
             allocate(aux(3,2*size(f%xcel,2)))
             aux(:,1:size(f%xcel,2)) = f%xcel
             call move_alloc(aux,f%xcel)
          end if
          read(lu,*) f%xcel(:,f%ncel0)
       end do
    end do
    call fclose(lu)
    allocate(aux(3,f%ncel0))
    aux = f%xcel(:,1:f%ncel0)
    call move_alloc(aux,f%xcel)

    ! allocate indices
    if (allocated(f%iesp)) deallocate(f%iesp)
    allocate(f%iesp(f%ncel0))
    nat = 0
    do i = 1, nspecies
       do j = 1, natoms(i)
          nat = nat + 1
          f%iesp(nat) = i
       end do
    end do
    deallocate(natoms)

  end subroutine elk_geometry

  !xx! private readers
  subroutine read_elk_state(f,filename)
    use tools_io, only: fopen_read, fclose
    use tools_math, only: cross, det
    use param, only: pi
    class(elkwfn), intent(inout) :: f
    character*(*), intent(in) :: filename

    integer :: lu, i, j, k, idum
    integer :: vdum(3)
    logical :: spin
    integer :: i1, i2, i3, j1, j2, j3, ig
    real*8 :: v(3), t1
    integer :: nspecies
    real*8, allocatable :: rhoktmp(:), rhotmp(:,:,:)
    real*8 :: bvec(3,3), omega
    integer :: intgv(3,2), ngrid(3)
    integer :: lmmaxvr
    integer :: ngrtot, nrmtmax
    ! allocatable arrays
    integer, allocatable :: idx(:)
    integer, allocatable :: iar(:)
    real*8, allocatable :: rar(:)
    real*8, allocatable :: gc(:)
    integer, allocatable :: ivg(:,:)
    integer :: nrcmtmax
    real*8, allocatable :: rcmt(:,:)
    
    ! inline for version checking
    logical :: isnewer
    isnewer(i,j,k) = (vdum(1)>i).or.(vdum(1)==i.and.vdum(2)>j).or.(vdum(1)==i.and.vdum(2)==j.and.vdum(3)>=k)

    ! open the file
    lu = fopen_read(filename,"unformatted")

    ! read header
    read(lu) vdum  ! version
    read(lu) spin  ! spinpol
    read(lu) nspecies  ! nspecies
    read(lu) lmmaxvr  ! lmmaxvr
    f%lmaxvr = nint(sqrt(real(lmmaxvr,8))) - 1

    ! allocate radial grids
    read(lu) nrmtmax ! nrmtmax
    if (allocated(f%spr)) deallocate(f%spr)
    if (allocated(f%spr_a)) deallocate(f%spr_a)
    if (allocated(f%spr_b)) deallocate(f%spr_b)
    allocate(f%spr(nrmtmax,nspecies),&
       f%spr_a(nspecies),f%spr_b(nspecies))

    ! read elk-2.1.25 
    if (isnewer(2,1,22)) then
       read(lu) nrcmtmax ! nrcmtmax
       if (allocated(rcmt)) deallocate(rcmt)
       allocate(rcmt(nrmtmax,nspecies))
    endif

    ! read rmt data
    if (allocated(f%nrmt)) deallocate(f%nrmt)
    if (allocated(f%rmt)) deallocate(f%rmt)
    allocate(f%nrmt(nspecies),f%rmt(nspecies))
    do i = 1, nspecies
       read(lu) idum  ! natoms(is)
       read(lu) f%nrmt(i)  ! nrmt(is)
       read(lu) f%spr(1:f%nrmt(i),i)  ! spr(1:nrmt(is),is)
       f%rmt(i) = f%spr(f%nrmt(i),i)
       f%spr_a(i) = f%spr(1,i)
       f%spr_b(i) = log(f%spr(f%nrmt(i),i) / &
          f%spr(1,i)) / real(f%nrmt(i)-1,8)
       if (isnewer(2,1,22)) then
          read(lu) idum  ! nrcmt(is)
          read(lu) rcmt(1:i,i)  ! rcmt(1:nrcmt(is),is)
       endif
    end do

    ! read interstitial data
    read(lu) f%n  ! ngridg
    ngrid = f%n
    read(lu) f%ngvec  ! ngvec
    read(lu) idum  ! ndmag
    read(lu) idum  ! nspinor
    if (isnewer(2,1,22)) then
       read(lu) idum  ! fixspin,fsmtype
    end if
    if(isnewer(2,3,16)) then
       read(lu) idum  ! ftmtype
    endif
    read(lu) idum  ! ldapu,dftu
    read(lu) idum  ! lmmaxdm,lmmaxlu
    ngrtot = ngrid(1)*ngrid(2)*ngrid(3)
    allocate(rhotmp(lmmaxvr,nrmtmax,f%ncel0))
    allocate(rhoktmp(ngrtot))

    ! read the density itself and close (there is more after this, ignored)
    read(lu) rhotmp, rhoktmp ! rhomt, rhoir
    call fclose(lu)

    ! reorder the rhotmp to rhomt
    if (allocated(f%rhomt)) deallocate(f%rhomt)
    allocate(f%rhomt(nrmtmax,lmmaxvr,f%ncel0))
    do i = 1, f%ncel0
       do j = 1, nrmtmax
          f%rhomt(j,:,i) = rhotmp(:,j,i)
       end do
    end do
    deallocate(rhotmp)

    ! fourier transform the interstitial density
    if (allocated(f%rhok)) deallocate(f%rhok)
    allocate(f%rhok(ngrtot))
    f%rhok = rhoktmp
    call cfftnd(3,ngrid,-1,f%rhok)
    deallocate(rhoktmp)

    ! generate the igfft
    bvec(:,1) = cross(f%x2c(:,2),f%x2c(:,3))
    bvec(:,2) = cross(f%x2c(:,3),f%x2c(:,1))
    bvec(:,3) = cross(f%x2c(:,1),f%x2c(:,2))
    omega = abs(det(f%x2c))
    bvec = 2d0 * pi / omega * bvec

    ! the reciprocal space spanned
    intgv(:,1)=ngrid(:)/2-ngrid(:)+1
    intgv(:,2)=ngrid(:)/2

    if (allocated(f%vgc)) deallocate(f%vgc)
    if (allocated(f%igfft)) deallocate(f%igfft)
    if (allocated(ivg)) deallocate(ivg)
    allocate(f%vgc(3,ngrtot))
    allocate(f%igfft(ngrtot))
    allocate(ivg(3,ngrtot))
    ! allocate local arrays
    allocate(idx(ngrtot))
    allocate(iar(ngrtot))
    allocate(rar(ngrtot))
    allocate(gc(ngrtot))

    ig = 0
    do i1=intgv(1,1),intgv(1,2)
       do i2=intgv(2,1),intgv(2,2)
          do i3=intgv(3,1),intgv(3,2)
             ig=ig+1
             v(:)=dble(i1)*bvec(:,1)+dble(i2)*bvec(:,2)+dble(i3)*bvec(:,3)
             t1=v(1)**2+v(2)**2+v(3)**2
             ! map from G-vector to (i1,i2,i3) index
             ivg(1,ig)=i1
             ivg(2,ig)=i2
             ivg(3,ig)=i3
             ! length of each G-vector
             gc(ig)=sqrt(t1)
          end do
       end do
    end do
    ! sort by vector length
    call sortidx(ngrtot,gc,idx)
    ! re-order arrays
    do ig=1,ngrtot
       rar(ig)=gc(ig)
    end do
    do ig=1,ngrtot
       gc(ig)=rar(idx(ig))
    end do
    do k=1,3
       do ig=1,ngrtot
          iar(ig)=ivg(k,ig)
       end do
       do ig=1,ngrtot
          ivg(k,ig)=iar(idx(ig))
       end do
    end do
    do i = 1, ngrtot
       i1=ivg(1,i)
       i2=ivg(2,i)
       i3=ivg(3,i)
       ! assign G-vectors to global array
       f%vgc(:,i)=dble(i1)*bvec(:,1)+dble(i2)*bvec(:,2)+dble(i3)*bvec(:,3)
       ! fourier transform index
       if (i1.ge.0) then
          j1=i1
       else
          j1=ngrid(1)+i1
       end if
       if (i2.ge.0) then
          j2=i2
       else
          j2=ngrid(2)+i2
       end if
       if (i3.ge.0) then
          j3=i3
       else
          j3=ngrid(3)+i3
       end if
       f%igfft(i)=j3*ngrid(2)*ngrid(1)+j2*ngrid(1)+j1+1
    end do

    ! deallocate local arrays
    deallocate(idx,iar,rar,gc,ivg)
    if (allocated(rcmt)) deallocate(rcmt)

  end subroutine read_elk_state

  !xx! private readers
  subroutine read_elk_myout(f,filename)
    use tools_io, only: ferror, faterr, fopen_read, fclose
    class(elkwfn), intent(inout) :: f
    character*(*), intent(in) :: filename

    integer :: lu, i, j
    integer :: lmmaxvr, nrmtmax, natmtot, ngrtot
    real*8, allocatable :: rhoktmp(:), rhotmp(:,:,:)

    ! open the file
    lu = fopen_read(filename,"unformatted")

    ! read header
    read(lu) lmmaxvr, nrmtmax, natmtot, ngrtot
    if (.not.allocated(f%rhomt).or..not.allocated(f%rhok)) &
       call ferror("read_elk_myout","field not allocated",faterr)
    if (size(f%rhomt,1) /= nrmtmax) &
       call ferror("read_elk_myout","wrong nrmtmax in field",faterr)
    if (size(f%rhomt,2) /= lmmaxvr) &
       call ferror("read_elk_myout","wrong lmmaxvr in field",faterr)
    if (size(f%rhomt,3) /= natmtot) &
       call ferror("read_elk_myout","wrong natmtot in field",faterr)
    if (size(f%rhok) /= ngrtot) &
       call ferror("read_elk_myout","wrong ngrtot in field",faterr)

    allocate(rhotmp(lmmaxvr,nrmtmax,natmtot))
    allocate(rhoktmp(ngrtot))

    ! read the density and close
    read(lu) rhotmp, rhoktmp
    call fclose(lu)

    ! reorder the rhotmp to rhomt
    f%rhomt = 0d0
    do i = 1, f%ncel0
       do j = 1, nrmtmax
          f%rhomt(j,:,i) = rhotmp(:,j,i)
       end do
    end do
    deallocate(rhotmp)

    ! fourier transform the interstitial density
    f%rhok = rhoktmp
    call cfftnd(3,f%n,-1,f%rhok)
    deallocate(rhoktmp)

  end subroutine read_elk_myout

  !> Calculate the density and its derivatives at a point in the unit
  !> cell vpl (crystallographic).  This routine is thread-safe.
  subroutine rho2(f,vpl,nder,frho,gfrho,hfrho)
    use tools_math, only: radial_derivs, tosphere, genylm, ylmderiv
    use tools_io, only: ferror, faterr
    class(elkwfn), intent(in) :: f
    real(8), intent(in) :: vpl(3)
    real(8), intent(out) :: frho, gfrho(3), hfrho(3,3)
    integer, intent(in) :: nder

    integer :: nid, lvec(3)
    real*8 :: dist
    integer :: i, j
    real*8 :: ct1, st1, fac1, fac2
    integer :: is
    integer :: ir0
    integer l,m,lm,ig,ifg
    real(8) r,tp(2), t0, t1, t2
    real(8) v1(3)
    complex*16 :: ylm((f%lmaxvr+1+2)**2)
    real*8 :: xrho, xgrad(3)
    complex*16 :: xgrad1(3), xgrad2(3)
    real*8 :: xhess(6)
    complex*16 :: xhess1(6), xhess2(6)
    real*8 :: isig

    integer :: elem
    real*8, parameter :: twopi1 = 1d0 / sqrt(2d0)
    complex*16, parameter :: twopi1i = 1d0 / sqrt(2d0) / (0d0,1d0)

    ! inline functions
    elem(l,m)=l*(l+1)+m+1
    !
    
    frho = 0d0
    gfrho = 0d0
    hfrho = 0d0
    nid = 0
    call local_nearest_atom(f,vpl,nid,dist,lvec)
    ! write (*,*) "vpl:", vpl
    ! do i = 1, f%ncel0
    !    write (*,*) i, matmul(f%x2c,f%xcel(:,i))
    ! end do
    ! write (*,*) "nid:", nid
    ! write (*,*) "pos:", matmul(f%x2c,f%xcel(:,nid))
    ! write (*,*) "dist:", dist
    ! write (*,*) "rhomt:", f%rhomt(1,1,:)
    
    ! inside a muffin tin
    is = f%iesp(nid)
    if (dist < f%rmt(is)) then
       v1 = vpl + lvec - f%xcel(:,nid)
       v1 = matmul(f%x2c,v1)
       call tosphere(v1,r,tp)
       if (abs(r-dist) > 1d-12) &
          call ferror("elk_rho2","invalid radius",faterr)
       call genylm(f%lmaxvr+2,tp,ylm)
       r = min(max(r,f%spr(1,is)),f%rmt(is))
       ir0 = min(max(floor(log(r / f%spr_a(is)) / &
          f%spr_b(is) + 1),1),f%nrmt(is))

       lm = 0
       isig = -1d0
       do l = 0, f%lmaxvr
          do m = -l, l
             !isig = (-1)**m
             isig = -isig
             lm = lm + 1
             call radial_derivs(f%rhomt(1:f%nrmt(is),lm,nid),t0,t1,t2,r,f%spr_a(is),f%spr_b(is))
             call ylmderiv(ylm,r,l,m,t0,t1,t2,xgrad1,xhess1)
             if (m /= 0) call ylmderiv(ylm,r,l,-m,t0,t1,t2,xgrad2,xhess2)
             if (m > 0) then
                xrho = real((ylm(elem(l,m)) + isig * ylm(elem(l,-m))),8) * twopi1
                xgrad = real(xgrad1 + isig * xgrad2,8) * twopi1
                xhess = real(xhess1 + isig * xhess2,8) * twopi1
             else if (m < 0) then
                xrho = real((ylm(elem(l,m)) - isig * ylm(elem(l,-m))) * twopi1i,8)
                xgrad = real((xgrad1 - isig * xgrad2) * twopi1i,8)
                xhess = real((xhess1 - isig * xhess2) * twopi1i,8)
             else
                xrho = dble(ylm(elem(l,0)))
                xgrad = real(xgrad1,8)
                xhess = real(xhess1,8)
             end if
             frho = frho + t0 * xrho
             gfrho = gfrho + xgrad
             do i = 1, 3
                hfrho(1,i) = hfrho(1,i) + xhess(i)
             end do
             hfrho(2,2) = hfrho(2,2) + xhess(4)
             hfrho(2,3) = hfrho(2,3) + xhess(5)
             hfrho(3,3) = hfrho(3,3) + xhess(6)
          end do
       end do

       ! nullify gradient at the nucleus
       if (dist < 1d-5) then
          gfrho = 0d0
       end if
    else
       ! interstitial
       v1 = matmul(f%x2c,vpl)
       do ig=1,f%ngvec
          ifg=f%igfft(ig)
          t1=f%vgc(1,ig)*v1(1)+f%vgc(2,ig)*v1(2)+f%vgc(3,ig)*v1(3)
          ct1 = cos(t1)
          st1 = sin(t1)
          fac1 = dble(f%rhok(ifg)*cmplx(ct1,st1,8))
          fac2 = dble(f%rhok(ifg)*cmplx(-st1,ct1,8))

          frho = frho + fac1
          if (nder <= 0) cycle
          gfrho = gfrho + fac2 * f%vgc(:,ig) 
          if (nder <= 1) cycle
          do i = 1, 3
             do j = i, 3
                hfrho(i,j) = hfrho(i,j) - fac1 * f%vgc(i,ig) * f%vgc(j,ig)
             end do
          end do
       end do
    end if

    ! fill missing hessian elements
    do i = 1, 3
       do j = i+1, 3
          hfrho(j,i) = hfrho(i,j)
       end do
    end do

    ! transform to derivatives wrt cryst coordinates
    gfrho = matmul(transpose(f%x2c),gfrho)
    hfrho = matmul(matmul(transpose(f%x2c),hfrho),f%x2c)

  end subroutine rho2

  subroutine sortidx(n,a,idx)
    ! !INPUT/OUTPUT PARAMETERS:
    !   n   : number of elements in array (in,integer)
    !   a   : real array (in,real(n))
    !   idx : permutation index (out,integer(n))
    ! !DESCRIPTION:
    !   Finds the permutation index {\tt idx} which sorts the real array {\tt a}
    !   into ascending order. No sorting of the array {\tt a} itself is performed.
    !   Uses the heapsort algorthim.
    !
    ! !REVISION HISTORY:
    !   Created October 2002 (JKD)
    !   Included tolerance eps, April 2006 (JKD)
    ! arguments
    integer, intent(in) :: n
    real(8), intent(in) :: a(n)
    integer, intent(out) :: idx(n)
    ! local variables
    integer i,j,k,l,m
    ! tolerance for deciding if one number is smaller than another
    real(8), parameter :: eps=1.d-14
    if (n.le.0) then
       write(*,*)
       write(*,'("Error(sortidx): n <= 0 : ",I8)') n
       write(*,*)
       stop
    end if
    do i=1,n
       idx(i)=i
    end do
    if (n.eq.1) return
    l=n/2+1
    k=n
10  continue
    if (l.gt.1) then
       l=l-1
       m=idx(l)
    else
       m=idx(k)
       idx(k)=idx(1)
       k=k-1
       if (k.eq.1) then
          idx(1)=m
          return
       end if
    end if
    i=l
    j=l+l
20  continue
    if (j.le.k) then
       if (j.lt.k) then
          if (a(idx(j)).lt.a(idx(j+1))+eps) j=j+1
       end if
       if (a(m).lt.a(idx(j))+eps) then
          idx(i)=idx(j)
          i=j
          j=j+j
       else
          j=k+1
       end if
       goto 20
    end if
    idx(i)=m
    goto 10
  end subroutine sortidx

  !> Convert a given wien2k scalar field into its laplacian.
  subroutine tolap(f)
    use tools_math, only: radial_derivs
    class(elkwfn), intent(inout) :: f

    integer :: ig, ifg
    real*8 :: krec2, rho, rho1, rho2
    integer :: nspecies
    integer :: l, lp1, m, lm, is, ir, iat
    real*8 :: r, r1, r2
    real*8, allocatable :: rgrid(:)

    ! atomic spheres
    nspecies = maxval(f%iesp)
    allocate(rgrid(size(f%rhomt,1)))
    do iat = 1, f%ncel0
       is = f%iesp(iat)
       lm = 0
       do l = 0, f%lmaxvr
          lp1 = l + 1
          do m = -l, l
             lm = lm + 1
             ! save the old radial grid
             rgrid = f%rhomt(1:f%nrmt(is),lm,iat)

             ! run over all radial points
             do ir = 1, f%nrmt(is)
                r = f%spr(ir,is)
                r1 = 1d0 / r
                r2 = r1 * r1
                call radial_derivs(rgrid(1:f%nrmt(is)),rho,rho1,rho2,r,f%spr_a(is),f%spr_b(is))
                f%rhomt(ir,lm,iat) = -l*lp1*rho*r2 + 2d0*r1*rho1 + rho2
             end do
          end do
       end do
    end do
    deallocate(rgrid)

    ! interstitial
    do ig = 1, f%ngvec
       ifg = f%igfft(ig)
       krec2 = -dot_product(f%vgc(:,ig),f%vgc(:,ig))
       f%rhok(ifg) = f%rhok(ifg) * krec2
    end do

  end subroutine tolap

  !> Calculate the nearest atom based on the structural information
  !> in elkwfn.
  subroutine local_nearest_atom(f,xp,nid,dist,lvec)
    class(elkwfn), intent(in) :: f
    real*8, intent(in) :: xp(:)
    integer, intent(inout) :: nid
    real*8, intent(out) :: dist
    integer, intent(out) :: lvec(3)
  
    real*8 :: temp(3), d2, d2min
    integer :: j, i1, i2, i3
  
    integer, parameter :: imax = 1

    d2min = 1d30
    do j= 1, f%ncel0
       do i1 = -imax, imax
          do i2 = -imax, imax
             do i3 = -imax, imax
                temp = f%xcel(:,j) - xp
                temp = temp - (nint(temp) + (/i1,i2,i3/))
                temp = matmul(f%x2c,temp)
                d2 = dot_product(temp,temp)
                if (d2 < d2min) then
                   nid = j
                   d2min = d2
                   lvec = nint(f%xcel(:,j) - xp) + (/i1,i2,i3/)
                end if
             end do
          end do
       end do
    end do
    dist = sqrt(d2min)
  
  end subroutine local_nearest_atom

end module elk_private

