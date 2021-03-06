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

! sysmod: system class and associated routines
module systemmod
  use hashmod, only: hash
  use types, only: integrable, pointpropable
  use fieldmod, only: field
  use crystalmod, only: crystal
  implicit none

  private

  public :: systemmod_init
  public :: systemmod_end
  private :: field_fcheck
  private :: field_feval
  private :: field_cube

  type system
     logical :: isinit = .false. !< Is the system initialized?
     type(crystal), pointer :: c => null() !< Crystal structure (always allocated)
     integer :: nf = -1 !< Number of fields
     type(field), allocatable :: f(:) !< Fields for this system
     logical :: refset = .false. !< Has the reference been set?
     integer :: iref = 0 !< Reference field
     integer :: npropi = 0 !< Number of integrable properties
     type(integrable), allocatable :: propi(:) !< Integrable properties
     integer :: npropp = 0 !< Number of properties at points
     type(pointpropable), allocatable :: propp(:) !< Properties at points
     type(hash) :: fh !< Hash of function aliases
     procedure(field_fcheck), nopass, pointer :: fcheck => null() !< Pointer to functions for arithmetics
     procedure(field_feval), nopass, pointer :: feval => null() !< Pointer to functions for arithmetics
     procedure(field_cube), nopass, pointer :: cube => null() !< Pointer to functions for arithmetics
   contains
     procedure :: end => system_end !< Terminate a system object
     procedure :: init => system_init !< Allocate space for crystal structure
     procedure :: reset_fields !< Reset fields, properties, and aliases to promolecular
     procedure :: set_reference !< Set a given field as reference
     procedure :: set_default_integprop !< Reset to default integrable properties
     procedure :: set_default_pointprop !< Reset to default point properties
     procedure :: report !< Write information about the system to the stdout
     procedure :: aliasstring !< A string containing the aliases of a given field
     procedure :: new_from_seed !< Build a system from a crystal seed
     procedure :: load_field_string !< Load a field using a command string
     procedure :: goodfield !< Returns true if the field is initialized
     procedure :: fieldname_to_idx !< Find the field ID from the alias
     procedure :: getfieldnum !< Find an open slot for a new field
     procedure :: field_copy !< Copy a field from one slot to another
     procedure :: unload_field !< Unload a field
     procedure :: new_integrable_string !< Define a field as integrable from a command
     procedure :: new_pointprop_string !< Define a field as point prop from a command
     procedure :: eval => system_eval !< Evaluate an arithmetic expression using the system's fields
     procedure :: propty !< Calculate the properties of a field or all fields at a point
     procedure :: grdall !< Calculate all integrable properties at a point
     procedure :: addcp !< Add a critical point to a field's CP list, maybe with discarding expr
  end type system
  public :: system

  ! Text-mode operation. Only one crystal and one system at a time.
  type(system), allocatable, target :: sy_(:)
  type(system), pointer :: sy => null()
  public :: sy

  ! integrable properties enumerate
  integer, parameter, public :: itype_v = 1
  integer, parameter, public :: itype_f = 2
  integer, parameter, public :: itype_fval = 3
  integer, parameter, public :: itype_gmod = 4
  integer, parameter, public :: itype_lap = 5
  integer, parameter, public :: itype_lapval = 6
  integer, parameter, public :: itype_expr = 7
  integer, parameter, public :: itype_mpoles = 8
  integer, parameter, public :: itype_deloc = 9
  character*10, parameter, public :: itype_names(9) = (/&
     "Volume    ","Field     ","Field (v) ","Gradnt mod","Laplacian ",&
     "Laplcn (v)","Expression","Multipoles","Deloc indx"/)
  
contains

  !> Allocate isy systems in the global variable. Make sy point to the
  !> first system.
  subroutine systemmod_init(isy)
    integer, intent(in) :: isy

    if (allocated(sy_)) deallocate(sy_)
    allocate(sy_(isy))
    sy => sy_(1)

  end subroutine systemmod_init

  !> Deallocate sy_
  subroutine systemmod_end()

    integer :: i

    if (allocated(sy_)) then
       do i = 1, size(sy_)
          call sy_(i)%end()
       end do
       deallocate(sy_)
    end if
    nullify(sy)

  end subroutine systemmod_end

  !> Deallocate the system variables and uninitialize
  subroutine system_end(s)
    class(system), intent(inout) :: s

    integer :: i

    if (associated(s%c)) then
       call s%c%end()
       deallocate(s%c)
    end if
    if (allocated(s%f)) then
       do i = 0, s%nf
          call s%f(i)%end()
       end do
       deallocate(s%f)
    end if
    s%nf = -1
    s%iref = 0
    s%refset = .false.
    s%npropi = 0
    if (allocated(s%propi)) deallocate(s%propi)
    s%npropp = 0
    if (allocated(s%propp)) deallocate(s%propp)
    s%isinit = .false.
    call s%fh%init()

  end subroutine system_end

  !> Initialize a system (allocate the crystal structure)
  subroutine system_init(s)
    class(system), intent(inout) :: s
    
    call s%end()
    allocate(s%c)
    s%fcheck => field_fcheck
    s%feval => field_feval
    s%cube => field_cube

  end subroutine system_init
  
  !> Reset the fields, properties, and aliases to the promolecular
  !> density.  
  subroutine reset_fields(s)
    class(system), intent(inout) :: s

    integer :: i

    if (.not.s%isinit) return
    if (.not.s%c%isinit) return

    ! set up the fields and the promolecular field
    if (allocated(s%f)) then
       do i = 0, s%nf
          call s%f(i)%end()
       end do
       deallocate(s%f)
    end if
    allocate(s%f(0:10))
    s%nf = 10
    call s%f(0)%load_promolecular(s%c,0,"<promolecular>")
    call s%fh%init()
    call s%fh%put("rho0",0)
    call s%f(0)%init_cplist
    call s%set_reference(0,.false.)
    s%refset = .false.

  end subroutine reset_fields

  !> Set a given field as reference. If maybe, set the field as
  !> reference only if no reference field has been set yet.
  subroutine set_reference(s,id,maybe)
    class(system), intent(inout) :: s
    integer, intent(in) :: id
    logical, intent(in) :: maybe

    if (.not.s%isinit) return
    if (.not.allocated(s%f) .or. .not.associated(s%c)) return
    if (.not.s%c%isinit) return
    if (id < 0 .or. id > size(s%f)) return
    if (.not.s%goodfield(id)) return
    if (maybe .and. s%refset) return
    
    s%iref = id
    s%refset = .true.

    ! reset integrable and point properties
    call s%set_default_integprop()
    call s%set_default_pointprop()

  end subroutine set_reference

  !> Reset the integrable properties to the default list
  subroutine set_default_integprop(s)
    class(system), intent(inout) :: s

    s%npropi = max(s%npropi,3)
    if (.not.allocated(s%propi)) allocate(s%propi(s%npropi))
    s%propi(1)%used = .true.
    s%propi(1)%itype = itype_v
    s%propi(1)%fid = 0
    s%propi(1)%prop_name = "Volume"
    s%propi(2)%used = .true.
    s%propi(2)%itype = itype_fval
    s%propi(2)%fid = s%iref
    s%propi(2)%prop_name = "Pop"
    s%propi(3)%used = .true.
    s%propi(3)%itype = itype_lapval
    s%propi(3)%fid = s%iref
    s%propi(3)%prop_name = "Lap"

  end subroutine set_default_integprop

  !> Reset the point properties to the default list
  subroutine set_default_pointprop(s)
    class(system), intent(inout) :: s

    if (.not.allocated(s%propp)) then
       allocate(s%propp(1))
       s%npropp = 0
    end if

  end subroutine set_default_pointprop

  !> Write information about the system to the standard output. lcrys
  !> = crystallographic information. lfield = list of fields. lpropi =
  !> integrable properties. lpropp = point properties. lalias = list
  !> of alias for the current fields. lzpsp = zpsp, core and
  !> pseudopotential charges.  linteg = integrable properties.
  !> lcp = summary of critical points for the reference field.
  subroutine report(s,lcrys,lfield,lpropi,lpropp,lalias,lzpsp,lcp)
    use tools_io, only: uout, string, ioj_right, ioj_center, ferror, faterr,&
       nameguess
    use param, only: maxzat0
    class(system), intent(inout) :: s
    logical, intent(in) :: lcrys
    logical, intent(in) :: lfield
    logical, intent(in) :: lpropi
    logical, intent(in) :: lpropp
    logical, intent(in) :: lalias
    logical, intent(in) :: lzpsp
    logical, intent(in) :: lcp

    integer :: i, j, nal
    character*4 :: sprop, yesno
    character(len=:), allocatable :: aux, str
    integer :: numclass(0:3), multclass(0:3)

    if (lcrys) call s%c%report(.true.,.true.)
    if (lfield) then
       write (uout,'("* List of scalar fields")')
       do i = 0, s%nf
          if (s%f(i)%isinit) then
             write (uout,'("+ Field number ",A)') string(i)
             call s%f(i)%printinfo(.true.,.true.)
             if (lalias) then
                call s%aliasstring(i,nal,str)
                if (nal > 0) &
                   write (uout,'("  Alias for this field (",A,"):",A)') string(nal), str
             end if
             if (s%iref == i) then
                write (uout,'("  This is the REFERENCE field.")') 
             end if
             write (uout,*)
          end if
       end do
    end if
    if (lpropi) then
       write (uout,'("* List of integrable properties (",A,")")') string(s%npropi)
       if (s%npropi > 0) then
          write (uout,'("# ",4(A,2X))') &
             string("Id",length=3,justify=ioj_right), string("Type",length=4,justify=ioj_center), &
             string("Field",length=5,justify=ioj_right), string("Name")
       end if
       do i = 1, s%npropi
          if (.not.s%propi(i)%used) cycle
          select case(s%propi(i)%itype)
          case(itype_v)
             sprop = "v"
          case(itype_f)
             sprop = "f"
          case(itype_fval)
             sprop = "fval"
          case(itype_gmod)
             sprop = "gmod"
          case(itype_lap)
             sprop = "lap"
          case(itype_lapval)
             sprop = "lval"
          case(itype_expr)
             sprop = "expr"
          case(itype_mpoles)
             sprop = "mpol"
          case(itype_deloc)
             sprop = "dloc"
          case default
             call ferror('report','unknown property',faterr)
          end select

          if (s%propi(i)%itype == itype_expr) then
             write (uout,'(2X,2(A,2X),2X,"""",A,"""")') &
                string(i,length=3,justify=ioj_right), string(sprop,length=4,justify=ioj_center), &
                string(s%propi(i)%expr)
          else
             write (uout,'(2X,4(A,2X))') &
                string(i,length=3,justify=ioj_right), string(sprop,length=4,justify=ioj_center), &
                string(s%propi(i)%fid,length=5,justify=ioj_right), string(s%propi(i)%prop_name)
          end if
       end do
       write (uout,*)
    end if

    if (lpropp) then
       write (uout,'("* List of additional properties at critical points (",A,")")') string(s%npropp)
       if (s%npropp > 0) then
          write(uout,'("# Id      Name       Expression")')
          do i = 1, s%npropp
             write (uout,'(2X,2(A,2X),2X,"""",A,"""")') &
                string(i,length=3,justify=ioj_right), &
                string(s%propp(i)%name,length=10,justify=ioj_center), &
                string(s%propp(i)%expr)
          end do
       end if
       write (uout,*)
    end if

    if (lzpsp .and. allocated(s%f)) then
       write (uout,'("* List of core and pseudopotential charges for each field")') 
       write (uout,'("# id  type   core?  ZPSP")')
       do i = 0, s%nf
          if (s%f(i)%isinit) then
             if (s%f(i)%usecore) then
                yesno = " yes"
             else
                yesno = " no "
             end if
             str = "  "
             do j = 1, maxzat0
                if (s%f(i)%zpsp(j) > 0) then
                   aux = str // string(nameguess(j,.true.)) // "(" // string(s%f(i)%zpsp(j)) // "), "
                   str = aux
                end if
             end do
             aux = str
             str = aux(1:len_trim(aux)-1)
             write (uout,'(2X,99(A,X))') string(i), string(s%f(i)%typestring(.true.),8,ioj_center),&
                yesno, str
          end if
       end do
       write (uout,*)
    end if

    if (lcp) then
       write (uout,'("* Summary of critical points for the reference field")')
       write (uout,'("  Non-equivalent critical points = ",A)') string(s%f(s%iref)%ncp)
       write (uout,'("  Cell critical points = ",A)') string(s%f(s%iref)%ncpcel)
       numclass = 0
       multclass = 0
       do i = 1, s%f(s%iref)%ncp
          numclass(s%f(s%iref)%cp(i)%typind) = numclass(s%f(s%iref)%cp(i)%typind) + 1
          multclass(s%f(s%iref)%cp(i)%typind) = multclass(s%f(s%iref)%cp(i)%typind) + s%f(s%iref)%cp(i)%mult
       end do
       write (uout,'("  Topological class (n|b|r|c): ",4(A,"(",A,") "))') &
          (string(numclass(i)),string(multclass(i)),i=0,3)
       if (s%c%ismolecule) then
          write (uout,'("  Poincare-Hopf sum: ",A)') string(multclass(0)-multclass(1)+multclass(2)-multclass(3))
       else
          write (uout,'("  Morse sum: ",A)') string(multclass(0)-multclass(1)+multclass(2)-multclass(3))
       endif
       write (uout,*)
    end if

  end subroutine report

  !> A string containing the aliases of a given field. Return the number
  !> of alias in nal.
  subroutine aliasstring(s,id,nal,str)
    use tools_io, only: string
    class(system), intent(in) :: s
    integer, intent(in) :: id
    integer, intent(out) :: nal
    character(len=:), allocatable, intent(out) :: str
    
    integer :: nn, j, val
    character(len=:), allocatable :: key, aux

    nal = 1
    str = " $" // string(id) // ","
    nn = s%fh%keys()
    do j = 1, nn
       key = s%fh%getkey(j)
       val = s%fh%get(key,0)
       if (val == id) then
          nal = nal + 1
          aux = trim(str) // " $" // string(key) // ","
          str = aux
       end if
    end do
    aux = str(1:len_trim(str)-1)
    str = trim(aux)
    
  end subroutine aliasstring

  !> Set up a new system using the information contained in a crystal
  !> seed. 
  subroutine new_from_seed(s,seed)
    use crystalseedmod, only: crystalseed
    class(system), intent(inout) :: s
    type(crystalseed), intent(in) :: seed
    
    call s%init()
    call s%c%struct_new(seed,.true.)

    if (s%c%isinit) then
       s%isinit = .true.

       ! fill environments, asterisms, nearest neighbors
       call s%c%struct_fill(.true.,-1,.false.,.true.,.false.)

       ! load the promolecular density field and set it as reference
       call s%reset_fields()
    else
       call s%end()
    end if

  end subroutine new_from_seed

  !> Load a new field from a command string. Return id number in id or
  !> -1 if failed. If the field could not be loaded, return the
  !> reason in errmsg.
  subroutine load_field_string(s,line,id,errmsg)
    use tools_io, only: getword, lgetword, equal, uout, string
    use fieldmod, only: realloc_field, type_grid, type_elk, type_wien
    use fieldseedmod, only: fieldseed
    use arithmetic, only: fields_in_eval
    use param, only: ifformat_copy, ifformat_as_lap, ifformat_as_grad, &
       ifformat_as_pot, ifformat_as_clm, ifformat_as_clm_sub, ifformat_as_ghost, &
       ifformat_as
    use iso_c_binding, only: c_loc, c_associated, c_ptr, c_f_pointer
    class(system), intent(inout), target :: s
    character*(*), intent(in) :: line
    integer, intent(out) :: id
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: i, oid, nal, id1, id2, nn, n(3)
    logical :: ok, isnewref
    type(fieldseed) :: seed
    integer :: idx
    character(len=:), allocatable :: str, aux
    character*255, allocatable :: idlist(:)
    type(system), pointer :: syl
    
    ! is the environment sane?
    id = -1
    if (.not.s%isinit) then
       errmsg = "system not initialized"
       return
    end if
    if (.not.s%c%isinit) then
       errmsg = "crystal not initialized"
       return
    end if
    if (.not.allocated(s%f)) then
       errmsg = "memory for fields not allocated"
       return
    end if

    ! Parse the line and build a field seed. Handle errors here,
    ! before allocating memory for a new field
    call seed%parse(line,.true.)
    if (len_trim(seed%errmsg) > 0) then
       id = -1
       errmsg = trim(seed%errmsg)
       return
    endif

    ! Maybe we can load it as a grid if all the fields are grids
    ! and they are the same size
    if (seed%iff == ifformat_as_ghost) then
       call fields_in_eval(seed%expr,s%fh,nn,idlist)
       ok = .true.
       n = -1
       do i = 1, nn
          ok = ok.and.s%goodfield(key=idlist(i))
          if (.not.ok) exit
          idx = s%fieldname_to_idx(idlist(i))
          ok = ok .and. (idx > 0 .and. idx <= s%nf) 
          if (.not.ok) exit
          ok = ok .and. (s%f(idx)%type == type_grid)
          if (.not.ok) exit
          if (any(n < 0)) then
             n = s%f(idx)%grid%n 
          else
             ok = ok .and. all(s%f(idx)%grid%n == n)
             if (.not.ok) exit
          end if
       end do
       ok = ok .and. all(n > 0)
       if (ok) then
          seed%n = n
          seed%iff = ifformat_as
       end if
    end if

    errmsg = ""
    if (seed%iff == ifformat_copy) then
       ! copy
       oid = s%fieldname_to_idx(seed%file(1))
       if (.not.s%goodfield(oid)) then
          errmsg = "wrong source field in LOAD COPY"
          return
       end if
       if (seed%nfile == 1) then
          id = s%getfieldnum()
       else
          id = s%fieldname_to_idx(seed%file(2))
          if (id < 0) then
             errmsg = "wrong target field in LOAD COPY"
             return
          end if
       end if
       call s%field_copy(oid,id)
       if (.not.s%f(id)%isinit) then
          call s%f(id)%end()
          errmsg = "failed copy"
          return
       end if
    elseif (seed%iff == ifformat_as_lap .or. seed%iff == ifformat_as_grad .or.&
       seed%iff == ifformat_as_pot) then
       ! load as lap/grad id.s
       oid = s%fieldname_to_idx(seed%ids)
       if (.not.s%goodfield(oid)) then
          errmsg = "wrong source field in LOAD AS LAP/GRAD/POT"
          return
       end if
       if (s%f(oid)%type == type_grid) then
          if (.not.s%f(oid)%grid%isinit) then
             errmsg = "the grid in source field of LOAD AS LAP/GRAD/POT is not initialized"
             return
          end if
          if (.not.allocated(s%f(oid)%grid%f)) then
             errmsg = "the grid in source field of LOAD AS LAP/GRAD/POT is not allocated"
             return
          end if
          id = s%getfieldnum()
          call s%f(id)%load_as_fftgrid(s%c,id,"<generated>",s%f(oid)%grid,seed%iff,seed%isry)
       elseif (s%f(oid)%type == type_wien .and. seed%iff == ifformat_as_lap) then
          id = s%getfieldnum()
          s%f(id) = s%f(oid)
          call s%f(id)%wien%tolap()
       elseif (s%f(oid)%type == type_elk .and. seed%iff == ifformat_as_lap) then
          id = s%getfieldnum()
          s%f(id) = s%f(oid)
          call s%f(id)%elk%tolap()
       else
          if (seed%iff == ifformat_as_lap) then
             errmsg = "LOAD AS LAP only with wien2k, elk and grid fields"
          else
             errmsg = "LOAD AS GRAD and POT only with grids}"
          end if
          return
       end if
    elseif (seed%iff == ifformat_as_clm.or.seed%iff == ifformat_as_clm_sub) then
       ! clm add/sub
       id1 = s%fieldname_to_idx(seed%ids)
       id2 = s%fieldname_to_idx(seed%ids2)
       if (.not.s%goodfield(id1).or..not.s%goodfield(id2)) then
          errmsg = "wrong field in CLM"
          return
       end if
       id = s%getfieldnum()
       s%f(id) = s%f(id1)

       if (s%f(id1)%type == type_elk.and.s%f(id2)%type == type_elk) then
          if (seed%iff == ifformat_as_clm) then
             s%f(id)%elk%rhomt = s%f(id)%elk%rhomt + s%f(id2)%elk%rhomt
             s%f(id)%elk%rhok = s%f(id)%elk%rhok + s%f(id2)%elk%rhok
          else
             s%f(id)%elk%rhomt = s%f(id)%elk%rhomt - s%f(id2)%elk%rhomt
             s%f(id)%elk%rhok = s%f(id)%elk%rhok - s%f(id2)%elk%rhok
          end if
       elseif (s%f(id1)%type == type_wien.and.s%f(id2)%type == type_wien) then
          if (seed%iff == ifformat_as_clm) then
             s%f(id)%wien%slm = s%f(id)%wien%slm + s%f(id2)%wien%slm
             s%f(id)%wien%sk = s%f(id)%wien%sk + s%f(id2)%wien%sk
             if (allocated(s%f(id)%wien%ski).and.allocated(s%f(id2)%wien%ski)) &
                s%f(id)%wien%ski = s%f(id)%wien%ski + s%f(id2)%wien%ski
          else
             s%f(id)%wien%slm = s%f(id)%wien%slm - s%f(id2)%wien%slm
             s%f(id)%wien%sk = s%f(id)%wien%sk - s%f(id2)%wien%sk
             if (allocated(s%f(id)%wien%ski).and.allocated(s%f(id2)%wien%ski)) &
                s%f(id)%wien%ski = s%f(id)%wien%ski - s%f(id2)%wien%ski
          end if
       else
          errmsg = "fields in CLM must be wien or elk and the same type"
          return
       end if
       call s%f(id)%init_cplist
    else
       ! rest
       id = s%getfieldnum()

       if (len_trim(seed%ids) > 0) then
          oid = s%fieldname_to_idx(seed%ids)
          if (.not.s%goodfield(oid)) then
             errmsg = "wrong field in SIZEOF"
             return
          end if
          if (s%f(oid)%type /= type_grid) then
             errmsg = "field in SIZEOF is not a grid"
             return
          end if
          if (.not.s%f(oid)%grid%isinit.or..not.allocated(s%f(oid)%grid%f)) then
             errmsg = "field in SIZEOF is not initialized"
             return
          end if
          seed%n = s%f(oid)%grid%n
       end if

       syl => s
       call s%f(id)%field_new(seed,s%c,id,s%fh,c_loc(syl),s%fcheck,s%feval,s%cube,errmsg)

       if (.not.s%f(id)%isinit .or. len_trim(errmsg) > 0) then
          call s%f(id)%end()
          return
       end if
    end if

    ! add to the field hash
    if (len_trim(seed%fid) > 0) &
       call s%fh%put(trim(seed%fid),id)

    ! set it as reference, if applicable
    isnewref = .not.s%refset
    call s%set_reference(id,.true.)

    ! write some info
    write (uout,'("+ Field number ",A)') string(id)
    call s%f(id)%printinfo(.true.,.true.)
    call s%aliasstring(id,nal,str)
    if (nal > 0) &
       write (uout,'("  Alias for this field (",A,"):",A)') string(nal), str
    write (uout,*)
    if (isnewref) then
       write (uout,'("* Field number ",A," is now REFERENCE."/)') string(id)
    end if

    ! Test the muffin tin discontinuity, if applicable. Ignore the
    ! error message.
    if (seed%testrmt) &
       call s%f(id)%testrmt(0,aux)

  end subroutine load_field_string

  !> Returns true if the field is initialized. The field can be
  !> indexed by number (id) or by key (key).
  function goodfield(s,id,key) result(ok)
    class(system), intent(in) :: s
    integer, intent(in), optional :: id
    character*(*), intent(in), optional :: key
    logical :: ok

    integer :: id0

    ok = .false.
    if (.not.allocated(s%f)) return
    if (present(id)) then
       id0 = id
    elseif (present(key)) then
       id0 = s%fieldname_to_idx(key)
    end if
    if (id0 < 0 .or. id0 > s%nf) return
    if (.not.s%f(id0)%isinit) return
    ok = .true.

  end function goodfield

  !> Convert a field name to the corresponding integer index.
  function fieldname_to_idx(s,id) result(fid)
    class(system), intent(in) :: s
    character*(*), intent(in) :: id
    integer :: fid

    character(len=:), allocatable :: oid
    integer :: ierr

    fid = -1
    oid = trim(adjustl(id))
    if (s%fh%iskey(oid)) then 
       fid = s%fh%get(oid,fid)
    else
       read(oid,*,iostat=ierr) fid
       if (ierr /= 0) fid = -1
    endif

  end function fieldname_to_idx

  !> Find an open slot for a new field
  integer function getfieldnum(s) result(id)
    use fieldmod, only: realloc_field
    use tools_io, only: string
    class(system), intent(inout) :: s
    logical :: found

    id = -1
    if (.not.allocated(s%f)) return

    found = .false.
    do id = 1, s%nf
       if (.not.s%f(id)%isinit) then
          found = .true.
          exit
       end if
    end do
    if (.not.found) then
       call realloc_field(s%f,s%nf+1)
       s%nf = s%nf + 1
       id = s%nf
    end if
    
  end function getfieldnum

  !> Copy a field from one slot to another
  subroutine field_copy(s,id0,id1)
    use fieldmod, only: realloc_field
    use tools_io, only: string
    class(system), intent(inout) :: s
    integer, intent(in) :: id0
    integer, intent(in) :: id1

    if (.not.allocated(s%f)) return
    if (.not.s%goodfield(id0)) return
    if (id1 > s%nf) then
       call realloc_field(s%f,id1)
       s%nf = id1
    end if
    if (s%f(id1)%isinit) call s%f(id1)%end()
    s%f(id1) = s%f(id0)
    s%f(id1)%id = id1
    call s%f(id1)%init_cplist

  end subroutine field_copy

  !> Check that the id is a grid and is a sane field. Wrapper around
  !> goodfield() to pass it to the arithmetic module.  This routine is
  !> thread-safe. psy is the pointer to the system.
  function field_fcheck(sptr,id,iout)
    use iso_c_binding, only: c_ptr, c_associated, c_f_pointer
    type(c_ptr), intent(in) :: sptr
    character*(*), intent(in) :: id
    integer, intent(out), optional :: iout
    logical :: field_fcheck

    type(system), pointer :: syl => null()
    integer :: iid

    call c_f_pointer(sptr,syl)
    field_fcheck = .false.
    if (.not.associated(syl)) return
    iid = syl%fieldname_to_idx(id)
    field_fcheck = syl%goodfield(iid)
    if (present(iout)) iout = iid

  end function field_fcheck

  !> Evaluate the field at a point. Wrapper around grd() to pass it to
  !> the arithmetic module.  This routine is thread-safe.
  recursive function field_feval(sptr,id,nder,fder,x0,periodic)
    use iso_c_binding, only: c_ptr, c_f_pointer
    use types, only: scalar_value
    use param, only: sqpi, pi
    type(scalar_value) :: field_feval
    type(c_ptr), intent(in) :: sptr
    character*(*), intent(in) :: id
    integer, intent(in) :: nder
    character*(*), intent(in) :: fder
    real*8, intent(in) :: x0(3)
    logical, intent(in), optional :: periodic

    type(system), pointer :: syl
    integer :: iid, lvec(3)
    real*8 :: xp(3), dist, u
    real*8, parameter :: rc = 1.4d0
    
    field_feval%f = 0d0
    field_feval%fval = 0d0
    field_feval%gf = 0d0
    field_feval%gfmod = 0d0
    field_feval%gfmodval = 0d0
    field_feval%hf = 0d0
    field_feval%del2f = 0d0
    field_feval%del2fval = 0d0
    field_feval%fspc = 0d0

    call c_f_pointer(sptr,syl)
    if (.not.associated(syl)) return
    iid = syl%fieldname_to_idx(id)
    if (iid >= 0) then
       call syl%f(iid)%grd(x0,nder,field_feval,fder=fder,periodic=periodic)
    elseif (trim(id) == "ewald") then
       xp = syl%c%c2x(x0)
       field_feval%f = syl%c%ewald_pot(xp,.false.)
       field_feval%fval = field_feval%f
    elseif (trim(id) == "model1r") then
       ! xxxx
       iid = 0
       xp = syl%c%c2x(x0)
       call syl%c%nearest_atom(xp,iid,dist,lvec)
       if (dist < rc) then
          u = dist/rc
          field_feval%f = (1 - 10*u**3 + 15*u**4 - 6*u**5) * 21d0 / (5d0 * pi * rc**3)
       else
          field_feval%f = 0d0
       end if
       field_feval%fval = field_feval%f
    elseif (trim(id) == "model1v") then
       ! xxxx requires the +1 charges
       iid = 0
       xp = syl%c%c2x(x0)
       call syl%c%nearest_atom(xp,iid,dist,lvec)
       field_feval%f = syl%c%ewald_pot(xp,.false.) + syl%c%qsum * syl%c%eta**2 * pi / syl%c%omega 
       if (dist < rc .and. dist > 1d-6) then ! correlates with the value in the ewald routine
          u = dist/rc
          field_feval%f = field_feval%f + (12 - 14*u**2 + 28*u**5 - 30*u**6 + 9*u**7) / (5d0 * rc) - 1d0 / dist
       elseif (dist <= 1d-6) then
          u = dist/rc
          field_feval%f = field_feval%f + (12 - 14*u**2 + 28*u**5 - 30*u**6 + 9*u**7) / (5d0 * rc) - 2d0 / sqpi / syl%c%eta
       end if
       field_feval%fval = field_feval%f
    end if

  end function field_feval

  !> Check that the field given by id is a grid of size n
  !> and return the grid, or return ifail = .true..
  function field_cube(sptr,n,id,fder,dry,ifail) result(q)
    use iso_c_binding, only: c_ptr, c_f_pointer
    use fieldmod, only: type_grid
    type(c_ptr), intent(in) :: sptr
    character*(*), intent(in) :: id
    integer, intent(in) :: n(3)
    character*(*), intent(in) :: fder
    logical, intent(in) :: dry
    logical, intent(out) :: ifail
    real*8 :: q(n(1),n(2),n(3))

    type(system), pointer :: syl
    integer :: iid
    logical :: isgrid

    call c_f_pointer(sptr,syl)

    ifail = .false.
    q = 0d0
    if (.not.associated(syl)) goto 999
    iid = syl%fieldname_to_idx(id)
    if (.not.syl%f(iid)%isinit) goto 999
    isgrid = (syl%f(iid)%type == type_grid)
    if (isgrid) isgrid = isgrid .and. all(syl%f(iid)%grid%n == n)
    if (isgrid) isgrid = isgrid .and. (trim(fder) == "" .or. trim(fder)=="v")
    if (isgrid) then
       if (.not.dry) then
          q = syl%f(iid)%grid%f
       else
          q = 0d0
       end if
    else
       goto 999
    end if

    return
999 continue
    ifail = .true.
    q = 0d0
  end function field_cube

  !> Unload a field given by identifier id.
  subroutine unload_field(s,id)
    class(system), intent(inout) :: s
    integer, intent(in) :: id

    integer :: i, idum, nkeys
    character*255, allocatable :: key(:)

    if (.not.s%isinit) return
    if (.not.allocated(s%f)) return
    if (id < 0 .or. id > s%nf) return
    if (.not.s%f(id)%isinit) return

    call s%f(id)%end()

    nkeys = s%fh%keys()
    allocate(key(nkeys))
    do i = 1, nkeys
       key(i) = s%fh%getkey(i)
    end do

    ! clear all alias referring to this field
    do i = 1, nkeys
       idum = s%fh%get(trim(key(i)),idum)
       if (idum == id) call s%fh%delkey(trim(key(i)))
    end do
    deallocate(key)

    ! if this field was reference, make the reference point to 0
    if (s%iref == id) then
       call s%set_reference(0,.false.)
       s%refset = .false.
    end if

  end subroutine unload_field

  !> Define fields as integrable. Atomic integrals for these fields
  !> will be calculated in the basins of the reference field.
  subroutine new_integrable_string(s,line,errmsg)
    use global, only: eval_next
    use tools_io, only: getword, lgetword, equal,&
       isexpression_or_word, string, isinteger, getline
    use types, only: realloc
    class(system), intent(inout) :: s
    character*(*), intent(in) :: line
    character(len=:), allocatable, intent(out) :: errmsg

    logical :: ok
    integer :: id, lp, lpold, idum
    character(len=:), allocatable :: word, expr, str
    logical :: useexpr

    lp=1
    useexpr = .false.
    errmsg = ""

    lpold = lp
    word = getword(line,lp)
    id = s%fieldname_to_idx(word)
    if (id < 0) then
       lp = lpold
       ! clear the integrable properties list
       word = lgetword(line,lp)
       if (equal(word,'clear')) then
          call s%set_default_integprop()
          return
       else 
          lp = lpold
          if (isexpression_or_word(expr,line,lp)) then
             useexpr = .true.
          else
             errmsg = "wrong syntax in INTEGRABLE"
             return
          endif
       end if
    else
       if (.not.s%goodfield(id)) then
          errmsg = "field " // string(id) // " not allocated"
          return
       end if
       str = "$" // string(word)
    end if

    ! add integrable property
    s%npropi = s%npropi + 1
    if (s%npropi > size(s%propi)) &
       call realloc(s%propi,2*s%npropi)
    if (useexpr) then
       s%propi(s%npropi)%used = .true.
       s%propi(s%npropi)%fid = 0
       s%propi(s%npropi)%itype = itype_expr
       s%propi(s%npropi)%prop_name = trim(adjustl(expr))
       s%propi(s%npropi)%expr = expr
    else
       s%propi(s%npropi)%used = .true.
       s%propi(s%npropi)%fid = id
       s%propi(s%npropi)%itype = itype_f
       s%propi(s%npropi)%prop_name = ""
       s%propi(s%npropi)%lmax = 5
       do while (.true.)
          word = lgetword(line,lp)
          if (equal(word,"f")) then
             s%propi(s%npropi)%itype = itype_f
             str = trim(str) // "#f"
          elseif (equal(word,"fval")) then
             s%propi(s%npropi)%itype = itype_fval
             str = trim(str) // "#fval"
          elseif (equal(word,"gmod")) then
             s%propi(s%npropi)%itype = itype_gmod
             str = trim(str) // "#gmod"
          elseif (equal(word,"lap")) then
             s%propi(s%npropi)%itype = itype_lap
             str = trim(str) // "#lap"
          elseif (equal(word,"lapval")) then
             s%propi(s%npropi)%itype = itype_lapval
             str = trim(str) // "#lapval"
          elseif (equal(word,"multipoles") .or. equal(word,"multipole")) then
             s%propi(s%npropi)%itype = itype_mpoles
             str = trim(str) // "#mpol"
             ok = isinteger(idum,line,lp)
             if (ok) s%propi(s%npropi)%lmax = idum
          elseif (equal(word,"deloc")) then
             s%propi(s%npropi)%itype = itype_deloc
             str = trim(str) // "#deloca"
          elseif (equal(word,"deloc")) then
             s%propi(s%npropi)%itype = itype_deloc
             str = trim(str) // "#deloca"
          elseif (equal(word,"name")) then
             word = getword(line,lp)
             s%propi(s%npropi)%prop_name = string(word)
          else if (len_trim(word) > 0) then
             errmsg = "Unknown extra keyword in INTEGRABLE"
             s%npropi = s%npropi - 1
             return
          else
             exit
          end if
       end do
       if (trim(s%propi(s%npropi)%prop_name) == "") then
          s%propi(s%npropi)%prop_name = str
       end if
    end if

  end subroutine new_integrable_string

  !> Define fields as point prop from a command string.
  subroutine new_pointprop_string(s,line0,errmsg)
    use tools_io, only: getword, lower, equal, string
    use arithmetic, only: fields_in_eval
    use types, only: realloc
    class(system), intent(inout) :: s
    character*(*), intent(in) :: line0
    character(len=:), allocatable, intent(out) :: errmsg

    logical :: isblank, isstress
    integer :: lp, n, i
    character(len=:), allocatable :: expr, word, lword, line
    character*255, allocatable :: idlist(:)

    errmsg = ""
    lp = 1
    line = line0
    word = getword(line,lp)
    isstress = .false.
    lword = lower(word)
    if (equal(lword,'clear')) then
       call s%set_default_pointprop()
       return
    elseif (equal(lword,'gtf')) then
       lp = 1 
       line = "gtf(" // string(s%iref) // ")"
    elseif (equal(lword,'vtf')) then
       lp = 1 
       line = "vtf(" // string(s%iref) // ")"
    elseif (equal(lword,'htf')) then
       lp = 1 
       line = "htf(" // string(s%iref) // ")"
    elseif (equal(lword,'gtf_kir')) then
       lp = 1 
       line = "gtf_kir(" // string(s%iref) // ")"
    elseif (equal(lword,'vtf_kir')) then
       lp = 1 
       line = "vtf_kir(" // string(s%iref) // ")"
    elseif (equal(lword,'htf_kir')) then
       lp = 1 
       line = "htf_kir(" // string(s%iref) // ")"
    elseif (equal(lword,'gkin')) then
       lp = 1 
       line = "gkin(" // string(s%iref) // ")"
    elseif (equal(lword,'kkin')) then
       lp = 1 
       line = "kkin(" // string(s%iref) // ")"
    elseif (equal(lword,'lag')) then
       lp = 1 
       line = "lag(" // string(s%iref) // ")"
    elseif (equal(lword,'elf')) then
       lp = 1 
       line = "elf(" // string(s%iref) // ")"
    elseif (equal(lword,'stress')) then
       lp = 1
       line = "stress(" // string(s%iref) // ")"
       isstress = .true.
    elseif (equal(lword,'vir')) then
       lp = 1 
       line = "vir(" // string(s%iref) // ")"
    elseif (equal(lword,'he')) then
       lp = 1 
       line = "he(" // string(s%iref) // ")"
    elseif (equal(lword,'lol')) then
       lp = 1 
       line = "lol(" // string(s%iref) // ")"
    elseif (equal(lword,'lol_kir')) then
       lp = 1 
       line = "lol_kir(" // string(s%iref) // ")"
    elseif (len_trim(lword) == 0) then
       return
    endif

    ! Clean up the string
    expr = ""
    isblank = .false.
    do i = lp, len_trim(line)
       if (line(i:i) == " ") then
          if (.not.isblank) then
             expr = expr // line(i:i)
             isblank = .true.
          end if
       elseif (line(i:i) /= """" .and. line(i:i) /= "'") then
          expr = expr // line(i:i)
          isblank = .false.
       endif
    end do
    expr = trim(adjustl(expr))
    if (len_trim(expr) == 0) then
       errmsg = "wrong arithmetic expression or unknown syntax in POINTPROP"
       return
    end if

    ! Add this pointprop to the list
    s%npropp = s%npropp + 1
    if (.not.allocated(s%propp)) allocate(s%propp(1))
    if (s%npropp > size(s%propp)) &
       call realloc(s%propp,2*s%npropp)
    s%propp(s%npropp)%name = word
    s%propp(s%npropp)%expr = expr
    if (isstress) then
       s%propp(s%npropp)%ispecial = 1
    else
       s%propp(s%npropp)%ispecial = 0
    end if

    ! Determine the fields in the expression, check that they are defined
    if (s%propp(s%npropp)%ispecial == 0) then
       call fields_in_eval(expr,s%fh,n,idlist)
       do i = 1, n
          if (.not.s%goodfield(s%fieldname_to_idx(idlist(i)))) then
             errmsg = "Unknown field in arithmetic expression (POINTPROP)"
             s%npropp = s%npropp - 1
             return
          end if
       end do

       ! fill the fused array
       if (allocated(s%propp(s%npropp)%fused)) deallocate(s%propp(s%npropp)%fused)
       allocate(s%propp(s%npropp)%fused(n))
       s%propp(s%npropp)%nf = n
       do i = 1, n
          s%propp(s%npropp)%fused(i) = s%fieldname_to_idx(idlist(i))
       end do
    else
       if (allocated(s%propp(s%npropp)%fused)) deallocate(s%propp(s%npropp)%fused)
       allocate(s%propp(s%npropp)%fused(1))
       s%propp(s%npropp)%nf = 1
       s%propp(s%npropp)%fused(1) = s%iref
    end if

    ! Clean up
    if (allocated(idlist)) deallocate(idlist)

  end subroutine new_pointprop_string
  
  !>x Evaluate an arithmetic expression using the system's fields  
  function system_eval(s,expr,hardfail,iok,x0) 
    use arithmetic, only: eval
    use iso_c_binding, only: c_loc
    class(system), intent(inout), target :: s
    character(*), intent(in) :: expr
    logical, intent(in) :: hardfail
    logical, intent(out) :: iok
    real*8, intent(in), optional :: x0(3)
    real*8 :: system_eval

    type(system), pointer :: syl

    syl => s
    system_eval = eval(expr,hardfail,iok,x0,c_loc(syl),s%fh,s%fcheck,s%feval)

  end function system_eval

  !> Calculate the properties of a field or all fields at a point plus
  !> the defined point properties of the system. The properties at
  !> point x0 (crystallographic) are calculated, followed by the value
  !> of all other fields at the point if allfields = .true.  Returns
  !> the properties in res and, if verbose is .true., write to the
  !> standard output.
  subroutine propty(s,id,x0,res,verbose,allfields)
    use global, only: cp_hdegen
    use tools_math, only: rsindex
    use tools_io, only: uout, string
    use arithmetic, only: eval
    use types, only: scalar_value
    class(system), intent(inout) :: s
    integer, intent(in) :: id
    real*8, dimension(:), intent(in) :: x0
    type(scalar_value), intent(out) :: res
    logical, intent(in) :: verbose
    logical, intent(in) :: allfields

    real*8 :: xp(3), fres, stvec(3,3), stval(3)
    integer :: str, sts
    integer :: i, j, k
    logical :: iok
    type(scalar_value) :: res2

    ! get the scalar field properties
    xp = s%c%x2c(x0)
    call s%f(id)%grd(xp,2,res)

    ! r and s
    res%hfevec = res%hf
    call rsindex(res%hfevec,res%hfeval,res%r,res%s,CP_hdegen)

    if (verbose) then
       if (res%isnuc) then
          write (uout,'("  Type : nucleus")') 
       else
          write (uout,'("  Type : (",a,",",a,")")') string(res%r), string(res%s)
       end if
       write (uout,'("  Field value (f): ",A)') string(res%f,'e',decimal=9)
       write (uout,'("  Field value, valence (fval): ",A)') string(res%fval,'e',decimal=9)
       write (uout,'("  Gradient (grad f): ",3(A,2X))') (string(res%gf(j),'e',decimal=9),j=1,3)
       write (uout,'("  Gradient norm (|grad f|): ",A)') string(res%gfmod,'e',decimal=9)
       write (uout,'("  Laplacian (del2 f): ",A)') string(res%del2f,'e',decimal=9)
       write (uout,'("  Laplacian, valence (del2 fval): ",A)') string(res%del2fval,'e',decimal=9)
       write (uout,'("  Hessian:")')
       do j = 1, 3
          write (uout,'(4x,1p,3(A,2X))') (string(res%hf(j,k),'e',decimal=9,length=16,justify=4), k = 1, 3)
       end do
       write (uout,'("  Hessian eigenvalues: ",3(A,2X))') (string(res%hfeval(j),'e',decimal=9),j=1,3)
       ! Write ellipticity, if it is a candidate for bond critical point
       if (res%r == 3 .and. res%s == -1 .and..not.res%isnuc) then
          write (uout,'("  Ellipticity (l_1/l_2 - 1): ",A)') string(res%hfeval(1)/res%hfeval(2)-1.d0,'e',decimal=9)
       endif

       ! properties at points defined by the user
       do i = 1, s%npropp
          if (s%propp(i)%ispecial == 0) then
             ! ispecial=0 ... use the expression
             fres = s%eval(s%propp(i)%expr,.true.,iok,xp)
             write (uout,'(2X,A," (",A,"): ",A)') string(s%propp(i)%name),&
                string(s%propp(i)%expr), string(fres,'e',decimal=9)
          else
             ! ispecial=1 ... schrodinger stress tensor
             stvec = res%stress
             call rsindex(stvec,stval,str,sts,CP_hdegen)
             write (uout,'("  Stress tensor:")')
             do j = 1, 3
                write (uout,'(4x,1p,3(A,2X))') (string(res%stress(j,k),'e',decimal=9,length=16,justify=4), k = 1, 3)
             end do
             write (uout,'("  Stress tensor eigenvalues: ",3(A,2X))') (string(stval(j),'e',decimal=9),j=1,3)
          endif
       end do

       ! rest of fields
       if (allfields) then
          do i = 0, s%nf
             if (s%goodfield(i) .and. i/=id) then
                call s%f(i)%grd(xp,2,res2)
                write (uout,'("  Field ",A," (f,|grad|,lap): ",3(A,2X))') string(i),&
                   string(res2%f,'e',decimal=9), string(res2%gfmod,'e',decimal=9), &
                   string(res2%del2f,'e',decimal=9)
             end if
          end do
       end if
    end if

  end subroutine propty

  !> Calculate the value of all integrable properties at the given
  !> position xpos (Cartesian). This routine is thread-safe.
  subroutine grdall(s,xpos,lprop,pmask)
    use types, only: scalar_value
    class(system), intent(inout) :: s
    real*8, intent(in) :: xpos(3) !< Point (cartesian).
    real*8, intent(out) :: lprop(s%npropi) !< the properties vector.
    logical, intent(in), optional :: pmask(s%npropi) !< properties mask

    type(scalar_value) :: res(0:ubound(s%f,1))
    logical :: fdone(0:ubound(s%f,1)), iok, pmask0(s%npropi)
    integer :: i, id

    if (present(pmask)) then
       pmask0 = pmask
    else
       pmask0 = .true.
    end if

    lprop = 0d0
    fdone = .false.
    do i = 1, s%npropi
       if (.not.pmask0(i)) cycle
       if (.not.s%propi(i)%used) cycle
       if (s%propi(i)%itype == itype_expr) then
          lprop(i) = s%eval(s%propi(i)%expr,.true.,iok,xpos)
       else
          id = s%propi(i)%fid
          if (.not.s%goodfield(id)) cycle
          if (.not.fdone(id).and.s%propi(i)%itype /= itype_v) then
             call s%f(id)%grd(xpos,2,res(id))
             fdone(id) = .true.
          end if

          select case(s%propi(i)%itype)
          case(itype_v)
             lprop(i) = 1
          case(itype_f)
             lprop(i) = res(id)%f
          case(itype_fval)
             lprop(i) = res(id)%fval
          case(itype_gmod)
             lprop(i) = res(id)%gfmod
          case(itype_lap)
             lprop(i) = res(id)%del2f
          case(itype_lapval)
             lprop(i) = res(id)%del2fval
          case(itype_mpoles)
             lprop(i) = res(id)%f
          case(itype_deloc)
             lprop(i) = res(id)%f
          case default
             cycle
          end select
       end if
    end do

  end subroutine grdall

  !> Try to add the candidate CP x0 to the CP list of field id. Calls
  !> addcp from fieldmod.  Checks if the CP is already known, and
  !> calculates all the relevant information: multiplicity, type,
  !> shell, assoc. nucleus, etc.  Also, updates the complete CP
  !> list. Input x0 in Cartesian. If itype is present, assign itype as
  !> the type of critical bond (-3,-1,1,3).  If discexpr has non-zero
  !> length, discard the critical point if it gives a non-zero value
  !> for this expression.
  subroutine addcp(s,id,x0,discexpr,cpeps,nuceps,nucepsh,itype)
    use tools_io, only: faterr, ferror
    class(system), intent(inout) :: s
    integer, intent(in) :: id
    real*8, intent(in) :: x0(3) !< Position of the CP, in Cartesian coordinates
    character*(*), intent(in) :: discexpr !< Discard expression
    real*8, intent(in) :: cpeps !< Discard CPs closer than cpeps from other CPs
    real*8, intent(in) :: nuceps !< Discard CPs closer than nuceps from nuclei
    real*8, intent(in) :: nucepsh !< Discard CPs closer than nucepsh from hydrogen
    integer, intent(in), optional :: itype !< Force a CP type (useful in grids)
    
    real*8 :: fval
    logical :: ok

    if (len_trim(discexpr) > 0) then
       fval = s%eval(discexpr,.false.,ok,x0)
       if (.not.ok) &
          call ferror("addcp","invalid DISCARD expression",faterr)
       ok = (abs(fval) < 1d-30)
       if (.not.ok) return
    end if
    call s%f(id)%addcp(x0,cpeps,nuceps,nucepsh,itype)

  end subroutine addcp

end module systemmod
