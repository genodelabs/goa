use std::fs;
use std::io;
use std::os::unix::fs::MetadataExt;

fn main() -> io::Result<()> {
    println!("Hello Genode Rust world!");

    // implicitly call libc's  'stat'
    let _metadata = fs::metadata("/dev/log")?;
    println!("{:?}", _metadata.file_type());
    println!("inode: {:?}", _metadata.ino());
    Ok(())
}
