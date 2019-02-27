module omp_fort

!f2py threadsafe
  use, intrinsic :: iso_c_binding, only: c_int
  use omp_lib
  implicit none
  
  public

  integer, dimension(:), allocatable, save :: rect_prev
  integer, dimension(:), allocatable :: rect_height
  integer, dimension(:), allocatable :: rect_done
  integer, dimension(:), allocatable :: job_done_by
  real, dimension(:), allocatable :: time
  real, dimension(:), allocatable :: my_work
  integer :: job_wait
  integer :: sched
  integer :: num_rect
  integer :: num_threads
  integer :: chunk
  logical :: computing
  logical :: finished
  integer :: max_height = 50

  interface
     function usleep (microseconds)  bind ( C, name="usleep" )
       import
       integer (c_int) :: usleep
       integer (c_int), intent (in), VALUE :: microseconds
     end function usleep
  end interface

contains

  
  subroutine init(shape, restore)

    implicit none
    integer, intent(in) :: shape
    logical, intent(in) :: restore
    integer :: i
    integer :: ierr

    ierr = 0
    finished = .false.
    ! Clean up potential old data
    if (allocated(time)) deallocate(time, stat=ierr)
    if (ierr.ne.0) stop 'Error deallocating time in init'
    if (allocated(my_work)) deallocate(my_work, stat=ierr)
    if (ierr.ne.0) stop 'Error deallocating my_work in init'

    job_wait = job_wait * 1000 !1 Millisecond per chunk

    allocate(time(num_threads), stat=ierr)
    if (ierr.ne.0) stop 'Error allocating time in init'
    time = 0.0
    allocate(my_work(num_threads), stat=ierr)
    if (ierr.ne.0) stop 'Error allocating my_work in init'
    my_work = 0.0
    
    if (.not. restore) then

       if (allocated(rect_height)) deallocate(rect_height, stat=ierr)
       if (ierr.ne.0) stop 'Error deallocating rect_height in init'
       if (allocated(rect_done)) deallocate(rect_done, stat=ierr)
       if (ierr.ne.0) stop 'Error deallocating rect_done in init'
       if (allocated(job_done_by)) deallocate(job_done_by, stat=ierr)
       if (ierr.ne.0) stop 'Error deallocating job_done_by in init'
       allocate(rect_height(num_rect),stat=ierr)
       if (ierr.ne.0) stop 'Error allocating rect_height in init'
       allocate(rect_done(num_rect), stat=ierr)
       if (ierr.ne.0) stop 'Error allocating rect_done in init'
       allocate(job_done_by(num_rect), stat=ierr)
       if (ierr.ne.0) stop 'Error allocating job_done_by in init'

       rect_done = 0
       job_done_by = 0
       
       !Allocate rect_prev array
       if (.not. allocated(rect_prev)) then
          allocate(rect_prev(num_rect),stat=ierr)
          if (ierr.ne.0) stop 'Error in allocating'
       else
          deallocate(rect_prev,stat=ierr)
          if (ierr.ne.0) stop 'Error in deallocating'
          allocate(rect_prev(num_rect),stat=ierr)
          if (ierr.ne.0) stop 'Error in deallocating'
       end if

       
       do i = 1,num_rect
          select case(shape)
          case(0) !Even
             rect_height(i) = max_height*0.6
          case(1) !Gradient
             rect_height(i) = i*((max_height-10)/num_rect)+10
          case(2) !Reverse Gradient
             rect_height(i) = max_height - i*((max_height-10)/num_rect)+10
          case(3) !Random
             rect_height(i) = generate_rand_int(max_height-30)+30
          case default
             rect_height(i) = max_height
          end select
          !Store values in case of reuse
          rect_prev(i) = rect_height(i)
       end do

    else
       !Reuse last run
       do i = 1, num_rect
          rect_height(i) = rect_prev(i)
          rect_done(i) = 0
       end do
    end if
  end subroutine init

  subroutine run()
    !f2py threadsafe
    implicit none
    integer(c_int) :: dump
    integer :: my_thread
    integer :: i
    integer :: height
    integer :: wait
    integer :: total_work
    
    ! Set up threads
    call omp_set_num_threads(num_threads)
    select case(sched)
    case(0)
       if (chunk == 0) chunk = num_rect/num_threads
       call omp_set_schedule(omp_sched_static,chunk)
    case(1)
       if (chunk == 0) chunk = 1
       call omp_set_schedule(omp_sched_dynamic,chunk)
    case(2)
       if (chunk == 0) chunk = num_rect/num_threads
       call omp_set_schedule(omp_sched_guided,chunk)
    case default
       if (chunk == 0) chunk = num_rect/num_threads
       call omp_set_schedule(omp_sched_static,chunk)
    end select

    total_work = sum(rect_height)

    computing = .true.
    !$omp parallel private(my_thread) default(shared)
    my_thread = omp_get_thread_num() + 1
    time(my_thread) = omp_get_wtime()
    !$omp do private(i, height, wait) schedule(runtime)
    main:do i = 1,num_rect
       my_work(my_thread) = my_work(my_thread) + real(rect_height(i))
       job_done_by(i) = my_thread
       if (.not. computing) continue !Break loop
       do while(rect_done(i) < rect_height(i))
          if (.not. computing) exit
          dump = usleep(job_wait)
          rect_done(i) = rect_done(i) + 1
       end do
    end do main
    !$omp end do nowait
    time(my_thread) = omp_get_wtime() - time(my_thread) 
    !$omp end parallel

    my_work = 100.0*my_work / real(total_work)
    finished = .true.
  end subroutine run

  function generate_rand_int(out_of)

    implicit none
    integer, parameter :: dp=selected_real_kind(15,300)
    real(kind=dp) :: rand
    integer :: generate_rand_int
    integer :: out_of

    call random_number(rand)
    generate_rand_int=ceiling(real(out_of,dp)*rand)

  end function generate_rand_int

end module omp_fort

