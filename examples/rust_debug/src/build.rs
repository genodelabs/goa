fn main() {
    // link to ld.lib.so in debug build mode (needed for wait_for_continue).
    #[cfg(debug_assertions)] {
        println!("cargo:rustc-link-arg=-l:ld.lib.so");
    }
}
