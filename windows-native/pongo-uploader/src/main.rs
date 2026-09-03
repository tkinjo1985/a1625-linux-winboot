#![cfg_attr(not(windows), allow(dead_code))]

use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

const PONGO_VENDOR_ID: u16 = 0x05ac;
const PONGO_PRODUCT_ID: u16 = 0x4141;
const MAX_UPLOAD_SIZE: u64 = 128 * 1024 * 1024;
const UPLOAD_CHUNK_SIZE: usize = 1024 * 1024;
const USB_TIMEOUT_MS: u32 = 30_000;

#[derive(Debug, PartialEq, Eq)]
enum Command {
    Validate { payload: PathBuf },
    Probe { libusb: PathBuf },
    Upload { payload: PathBuf, libusb: PathBuf },
    Help,
}

fn usage() -> &'static str {
    "Usage:\n\
  atv-pongo-uploader validate <m1n1-linux.bin>\n\
  atv-pongo-uploader probe --libusb <absolute-libusb-1.0.dll>\n\
  atv-pongo-uploader upload <m1n1-linux.bin> --libusb <absolute-libusb-1.0.dll> --confirm-ram-boot\n\n\
Upload is accepted only for PongoOS USB 05ac:4141. No DFU exploit, driver, restore,\n\
NVRAM, partition, or internal-storage operation is implemented."
}

fn parse_args(args: &[String]) -> Result<Command, String> {
    let Some(command) = args.first().map(String::as_str) else {
        return Ok(Command::Help);
    };

    match command {
        "help" | "--help" | "-h" => Ok(Command::Help),
        "validate" => {
            if args.len() != 2 {
                return Err("validate requires exactly one payload path".into());
            }
            Ok(Command::Validate {
                payload: PathBuf::from(&args[1]),
            })
        }
        "probe" => {
            let libusb = parse_option_path(args, "--libusb")?;
            if args.len() != 3 {
                return Err("probe accepts only --libusb <absolute-path>".into());
            }
            require_absolute_dll(&libusb)?;
            Ok(Command::Probe { libusb })
        }
        "upload" => {
            if args.len() != 5 {
                return Err(
                    "upload requires a payload, --libusb path, and --confirm-ram-boot".into(),
                );
            }
            let payload = PathBuf::from(&args[1]);
            let libusb = parse_option_path(args, "--libusb")?;
            require_absolute_dll(&libusb)?;
            if !args.iter().any(|arg| arg == "--confirm-ram-boot") {
                return Err("refusing USB transfer without --confirm-ram-boot".into());
            }
            Ok(Command::Upload { payload, libusb })
        }
        other => Err(format!("unknown command: {other}")),
    }
}

fn parse_option_path(args: &[String], option: &str) -> Result<PathBuf, String> {
    let index = args
        .iter()
        .position(|arg| arg == option)
        .ok_or_else(|| format!("missing {option}"))?;
    let value = args
        .get(index + 1)
        .ok_or_else(|| format!("missing value after {option}"))?;
    Ok(PathBuf::from(value))
}

fn require_absolute_dll(path: &Path) -> Result<(), String> {
    if !path.is_absolute() {
        return Err("--libusb must be an absolute path".into());
    }
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    if !file_name.eq_ignore_ascii_case("libusb-1.0.dll") {
        return Err("--libusb must point to a file named libusb-1.0.dll".into());
    }
    Ok(())
}

fn validate_payload(path: &Path) -> Result<u64, String> {
    let metadata =
        fs::metadata(path).map_err(|error| format!("cannot read payload metadata: {error}"))?;
    if !metadata.is_file() {
        return Err("payload is not a regular file".into());
    }
    let size = metadata.len();
    if size == 0 {
        return Err("payload is empty".into());
    }
    if size > MAX_UPLOAD_SIZE {
        return Err(format!(
            "payload is larger than PongoOS limit ({MAX_UPLOAD_SIZE} bytes)"
        ));
    }
    if size > u32::MAX as u64 {
        return Err("payload size does not fit the PongoOS 32-bit length field".into());
    }
    Ok(size)
}

#[cfg(windows)]
mod native {
    use super::*;
    use std::ffi::{CString, OsStr, c_char, c_int, c_uchar, c_uint, c_ushort, c_void};
    use std::mem::transmute;
    use std::os::windows::ffi::OsStrExt;
    use std::ptr::null_mut;

    type LibusbContext = c_void;
    type LibusbDeviceHandle = c_void;
    type Hmodule = *mut c_void;

    unsafe extern "system" {
        fn LoadLibraryW(name: *const u16) -> Hmodule;
        fn GetProcAddress(module: Hmodule, name: *const c_char) -> *mut c_void;
        fn FreeLibrary(module: Hmodule) -> c_int;
    }

    type InitFn = unsafe extern "C" fn(*mut *mut LibusbContext) -> c_int;
    type ExitFn = unsafe extern "C" fn(*mut LibusbContext);
    type OpenFn =
        unsafe extern "C" fn(*mut LibusbContext, c_ushort, c_ushort) -> *mut LibusbDeviceHandle;
    type CloseFn = unsafe extern "C" fn(*mut LibusbDeviceHandle);
    type SetConfigurationFn = unsafe extern "C" fn(*mut LibusbDeviceHandle, c_int) -> c_int;
    type ClaimInterfaceFn = unsafe extern "C" fn(*mut LibusbDeviceHandle, c_int) -> c_int;
    type ReleaseInterfaceFn = unsafe extern "C" fn(*mut LibusbDeviceHandle, c_int) -> c_int;
    type ControlTransferFn = unsafe extern "C" fn(
        *mut LibusbDeviceHandle,
        c_uchar,
        c_uchar,
        c_ushort,
        c_ushort,
        *mut c_uchar,
        c_ushort,
        c_uint,
    ) -> c_int;
    type BulkTransferFn = unsafe extern "C" fn(
        *mut LibusbDeviceHandle,
        c_uchar,
        *mut c_uchar,
        c_int,
        *mut c_int,
        c_uint,
    ) -> c_int;
    type ErrorNameFn = unsafe extern "C" fn(c_int) -> *const c_char;

    struct LibUsb {
        module: Hmodule,
        init: InitFn,
        exit: ExitFn,
        open: OpenFn,
        close: CloseFn,
        set_configuration: SetConfigurationFn,
        claim_interface: ClaimInterfaceFn,
        release_interface: ReleaseInterfaceFn,
        control_transfer: ControlTransferFn,
        bulk_transfer: BulkTransferFn,
        error_name: ErrorNameFn,
    }

    impl Drop for LibUsb {
        fn drop(&mut self) {
            unsafe {
                FreeLibrary(self.module);
            }
        }
    }

    impl LibUsb {
        fn load(path: &Path) -> Result<Self, String> {
            let wide: Vec<u16> = OsStr::new(path.as_os_str())
                .encode_wide()
                .chain(Some(0))
                .collect();
            let module = unsafe { LoadLibraryW(wide.as_ptr()) };
            if module.is_null() {
                return Err(format!("LoadLibraryW failed for {}", path.display()));
            }

            macro_rules! load {
                ($name:literal, $ty:ty) => {{
                    let name = CString::new($name).expect("static symbol has no NUL");
                    let address = unsafe { GetProcAddress(module, name.as_ptr()) };
                    if address.is_null() {
                        unsafe {
                            FreeLibrary(module);
                        }
                        return Err(format!("missing libusb symbol: {}", $name));
                    }
                    unsafe { transmute::<*mut c_void, $ty>(address) }
                }};
            }

            Ok(Self {
                module,
                init: load!("libusb_init", InitFn),
                exit: load!("libusb_exit", ExitFn),
                open: load!("libusb_open_device_with_vid_pid", OpenFn),
                close: load!("libusb_close", CloseFn),
                set_configuration: load!("libusb_set_configuration", SetConfigurationFn),
                claim_interface: load!("libusb_claim_interface", ClaimInterfaceFn),
                release_interface: load!("libusb_release_interface", ReleaseInterfaceFn),
                control_transfer: load!("libusb_control_transfer", ControlTransferFn),
                bulk_transfer: load!("libusb_bulk_transfer", BulkTransferFn),
                error_name: load!("libusb_error_name", ErrorNameFn),
            })
        }

        fn error(&self, operation: &str, code: c_int) -> String {
            let pointer = unsafe { (self.error_name)(code) };
            let name = if pointer.is_null() {
                "unknown"
            } else {
                unsafe { std::ffi::CStr::from_ptr(pointer) }
                    .to_str()
                    .unwrap_or("invalid-error-name")
            };
            format!("{operation} failed: {name} ({code})")
        }
    }

    struct Session<'a> {
        usb: &'a LibUsb,
        context: *mut LibusbContext,
        handle: *mut LibusbDeviceHandle,
        claimed: bool,
    }

    impl Drop for Session<'_> {
        fn drop(&mut self) {
            unsafe {
                if self.claimed {
                    (self.usb.release_interface)(self.handle, 0);
                }
                if !self.handle.is_null() {
                    (self.usb.close)(self.handle);
                }
                if !self.context.is_null() {
                    (self.usb.exit)(self.context);
                }
            }
        }
    }

    impl<'a> Session<'a> {
        fn open(usb: &'a LibUsb, claim: bool) -> Result<Self, String> {
            let mut context = null_mut();
            let result = unsafe { (usb.init)(&mut context) };
            if result != 0 {
                return Err(usb.error("libusb_init", result));
            }

            let handle = unsafe { (usb.open)(context, PONGO_VENDOR_ID, PONGO_PRODUCT_ID) };
            if handle.is_null() {
                unsafe {
                    (usb.exit)(context);
                }
                return Err("PongoOS 05ac:4141 not found or its driver is inaccessible".into());
            }

            let mut session = Self {
                usb,
                context,
                handle,
                claimed: false,
            };
            if claim {
                let result = unsafe { (usb.set_configuration)(handle, 1) };
                if result != 0 {
                    return Err(usb.error("libusb_set_configuration(1)", result));
                }
                let result = unsafe { (usb.claim_interface)(handle, 0) };
                if result != 0 {
                    return Err(usb.error("libusb_claim_interface(0)", result));
                }
                session.claimed = true;
            }
            Ok(session)
        }

        fn control(&self, request: u8, data: &mut [u8]) -> Result<(), String> {
            let result = unsafe {
                (self.usb.control_transfer)(
                    self.handle,
                    0x21,
                    request,
                    0,
                    0,
                    data.as_mut_ptr(),
                    data.len() as u16,
                    USB_TIMEOUT_MS,
                )
            };
            if result < 0 {
                return Err(self.usb.error("libusb_control_transfer", result));
            }
            if result as usize != data.len() {
                return Err(format!(
                    "short control transfer: {result}/{} bytes",
                    data.len()
                ));
            }
            Ok(())
        }

        fn upload(&self, payload: &Path, size: u64) -> Result<(), String> {
            let mut size_bytes = (size as u32).to_le_bytes();
            self.control(1, &mut size_bytes)?;

            let mut file =
                File::open(payload).map_err(|error| format!("cannot open payload: {error}"))?;
            let mut buffer = vec![0u8; UPLOAD_CHUNK_SIZE];
            let mut total = 0u64;
            loop {
                let count = file
                    .read(&mut buffer)
                    .map_err(|error| format!("payload read failed: {error}"))?;
                if count == 0 {
                    break;
                }
                let mut offset = 0usize;
                while offset < count {
                    let mut transferred = 0;
                    let result = unsafe {
                        (self.usb.bulk_transfer)(
                            self.handle,
                            0x02,
                            buffer[offset..count].as_mut_ptr(),
                            (count - offset) as c_int,
                            &mut transferred,
                            USB_TIMEOUT_MS,
                        )
                    };
                    if result != 0 {
                        return Err(self.usb.error("libusb_bulk_transfer(0x02)", result));
                    }
                    if transferred <= 0 {
                        return Err("bulk transfer made no progress".into());
                    }
                    offset += transferred as usize;
                    total += transferred as u64;
                }
            }
            if total != size {
                return Err(format!(
                    "payload length changed while reading: {total}/{size}"
                ));
            }

            let mut command = b"bootm\n".to_vec();
            self.control(3, &mut command)
        }
    }

    pub fn probe(libusb_path: &Path) -> Result<(), String> {
        let usb = LibUsb::load(libusb_path)?;
        let _session = Session::open(&usb, false)?;
        println!("PongoOS 05ac:4141 is accessible; no USB transfer was sent.");
        Ok(())
    }

    pub fn upload(libusb_path: &Path, payload: &Path, size: u64) -> Result<(), String> {
        let usb = LibUsb::load(libusb_path)?;
        let session = Session::open(&usb, true)?;
        session.upload(payload, size)?;
        println!("Uploaded {size} bytes and sent bootm to PongoOS.");
        Ok(())
    }
}

#[cfg(not(windows))]
mod native {
    use super::*;
    pub fn probe(_: &Path) -> Result<(), String> {
        Err("this prototype supports Windows only".into())
    }
    pub fn upload(_: &Path, _: &Path, _: u64) -> Result<(), String> {
        Err("this prototype supports Windows only".into())
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    match parse_args(&args)? {
        Command::Help => println!("{}", usage()),
        Command::Validate { payload } => {
            let size = validate_payload(&payload)?;
            println!("Payload passes structural preflight: {} bytes", size);
            println!("This does not prove the target, DTB, page size, or initramfs contents.");
        }
        Command::Probe { libusb } => native::probe(&libusb)?,
        Command::Upload { payload, libusb } => {
            let size = validate_payload(&payload)?;
            native::upload(&libusb, &payload, size)?;
        }
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("error: {error}\n\n{}", usage());
        std::process::exit(2);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_owned()).collect()
    }

    #[test]
    fn upload_requires_confirmation() {
        let error = parse_args(&strings(&[
            "upload",
            "image.bin",
            "--libusb",
            r"C:\tools\libusb-1.0.dll",
            "--wrong-flag",
        ]))
        .unwrap_err();
        assert!(error.contains("confirm-ram-boot"));
    }

    #[test]
    fn relative_dll_is_rejected() {
        let error = parse_args(&strings(&["probe", "--libusb", "libusb-1.0.dll"])).unwrap_err();
        assert!(error.contains("absolute"));
    }

    #[test]
    fn valid_upload_arguments_are_accepted() {
        let command = parse_args(&strings(&[
            "upload",
            "image.bin",
            "--libusb",
            r"C:\tools\libusb-1.0.dll",
            "--confirm-ram-boot",
        ]))
        .unwrap();
        assert!(matches!(command, Command::Upload { .. }));
    }
}
