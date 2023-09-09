extern "C" {
    #![allow(unused)]
    fn wait_for_continue();
}

fn main() {
    // Invoke wait_for_continue only in debug build mode (--debug switch).
    #[cfg(debug_assertions)]
    unsafe {
        println!("(debug mode) waiting for debugger");
        wait_for_continue();
    }

    println!("Hello Genode Rust world!");
}
