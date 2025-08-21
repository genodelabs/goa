project('hello_meson', 'cpp')

forty_two = library('forty_two', ['lib.cc'],
                    include_directories: include_directories('include'),
                    install: true,)

executable('hello',
           'hello.cc',
           include_directories: include_directories('include'),
           link_with: forty_two,
           install: true,)

