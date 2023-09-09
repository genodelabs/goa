use std::io;

extern "C" {
    fn wait_for_continue();
}

fn main() -> io::Result<()> {
    // Invoke wait_for_continue only in debug build mode (--debug switch).
    #[cfg(debug_assertions)]
    unsafe {
        println!("(debug mode) waiting for debugger");
        wait_for_continue();
    }

    println!("Hello Genode Rust world!");

    Ok(())
}
