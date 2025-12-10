use nix::errno::Errno;
use nix::fcntl::{self, FcntlArg};
use nix::libc;
use nix::poll::{poll, PollFd, PollFlags};
use nix::sys::signal::{self, SigHandler, Signal};
use nix::sys::socket::{
    self, AddressFamily, Inet6Addr, InetAddr, SockAddr, SockFlag, SockProtocol, SockType,
    SockaddrIn, SockaddrIn6, SockaddrLinkLayer, SockaddrUnix,
};
use nix::sys::stat::Mode;
use nix::sys::time::{TimeVal, TimeValLike};
use nix::sys::wait::WaitStatus;
use nix::unistd::{self, close, fork, write};
use socket2::{Domain, Protocol, Socket, Type};
use std::env;
use std::io::{self, Read, Write};
use std::os::unix::io::{AsRawFd, FromRawFd, RawFd};
use std::process;
use std::str;
use std::time::Duration;

// Veth struct (from previous translation)
#[derive(Debug)]
pub struct Veth {
    name: String,
    peer: String,
    peer_mac: Option<[u8; 6]>,
    peer_ifindex: Option<i32>,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

impl Veth {
    pub fn init(name: &str) -> Self {
        let peer = format!("{}-peer", name);
        Self {
            name: name.to_string(),
            peer,
            peer_mac: None,
            peer_ifindex: None,
            stdout: Vec::new(),
            stderr: Vec::new(),
        }
    }

    fn run_cmd(&mut self, cmd: &[&str]) -> io::Result<u8> {
        self.stdout.clear();
        self.stderr.clear();

        let mut child = std::process::Command::new(cmd[0])
            .args(&cmd[1..])
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        let stdout = child.stdout.take().unwrap();
        let stderr = child.stderr.take().unwrap();

        let mut stdout_data = Vec::new();
        let mut stderr_data = Vec::new();
        std::io::copy(&mut stdout, &mut stdout_data)?;
        std::io::copy(&mut stderr, &mut stderr_data)?;

        self.stdout = stdout_data;
        self.stderr = stderr_data;

        let status = child.wait()?;
        Ok(status.code().unwrap_or(1))
    }

    pub fn create_veth(&mut self, veth_cidr: &str) -> io::Result<()> {
        let cmds = [
            (&["ip", "link", "show", &self.name], 1),
            (
                &[
                    "ip", "link", "add", &self.name, "type", "veth", "peer", "name", &self.peer,
                ],
                0,
            ),
            (&["ip", "addr", "add", veth_cidr, "dev", &self.name], 0),
            (&["ip", "link", "set", &self.name, "up"], 0),
            (&["ip", "link", "set", &self.peer, "up"], 0),
        ];

        for (cmd, expected) in &cmds {
            let exit_code = self.run_cmd(cmd)?;
            if exit_code != *expected {
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!("Command failed (expected {}, got {})", expected, exit_code),
                ));
            }
        }
        Ok(())
    }

    pub fn get_peer_mac(&mut self) -> io::Result<[u8; 6]> {
        if let Some(mac) = self.peer_mac {
            return Ok(mac);
        }
        self.update_peer_info()?;
        self.peer_mac
            .ok_or_else(|| io::Error::new(io::ErrorKind::Other, "Peer MAC not found after update"))
    }

    pub fn get_peer_ifindex(&mut self) -> io::Result<i32> {
        if let Some(idx) = self.peer_ifindex {
            return Ok(idx);
        }
        self.update_peer_info()?;
        self.peer_ifindex.ok_or_else(|| {
            io::Error::new(io::ErrorKind::Other, "Peer ifindex not found after update")
        })
    }

    fn update_peer_info(&mut self) -> io::Result<()> {
        self.stdout.clear();
        self.stderr.clear();

        let cmd = &["ip", "-j", "link", "show", &self.peer];
        let exit_code = self.run_cmd(cmd)?;
        if exit_code != 0 {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                "ip -j link show command failed",
            ));
        }

        let json_str = str::from_utf8(&self.stdout).map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid UTF-8 in command output",
            )
        })?;

        let parsed: Vec<VethJsonIface> = serde_json::from_str(json_str)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;

        if parsed.is_empty() {
            return Err(io::Error::new(io::ErrorKind::NotFound, "No devices found"));
        }
        if parsed.len() > 1 {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                "Multiple devices found (expected exactly one)",
            ));
        }

        let iface = &parsed[0];
        let mac_str = iface
            .address
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::Other, "Address field missing in JSON"))?;

        let mut mac = [0u8; 6];
        Self::string_to_mac(mac_str, &mut mac)?;
        self.peer_mac = Some(mac);
        self.peer_ifindex = Some(iface.ifindex);
        Ok(())
    }

    fn string_to_mac(mac_str: &str, mac: &mut [u8; 6]) -> io::Result<()> {
        let parts: Vec<&str> = mac_str.split(':').collect();
        if parts.len() != 6 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid MAC format (expected 6 hex pairs)",
            ));
        }
        for (i, part) in parts.iter().enumerate() {
            mac[i] = u8::from_str_radix(part, 16)
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "Invalid hex digit"))?;
        }
        Ok(())
    }

    pub fn destroy(&mut self) {
        let cmds = [
            &["ip", "link", "set", &self.name, "down"],
            &["ip", "link", "set", &self.peer, "down"],
            &["ip", "link", "del", &self.name],
        ];

        for cmd in &cmds {
            let _ = self.run_cmd(cmd);
        }
    }
}

#[derive(Debug, serde::Deserialize)]
struct VethJsonIface {
    ifindex: i32,
    ifname: String,
    flags: Vec<String>,
    mtu: i32,
    qdisc: String,
    operstate: String,
    linkmode: String,
    group: String,
    link_type: String,
    link: Option<String>,
    master: Option<String>,
    txqlen: Option<i32>,
    address: Option<String>,
    broadcast: Option<String>,
    altnames: Option<Vec<String>>,
}

// Signal handling for SIGINT
static mut QUIT_LOOP: bool = false;

extern "C" fn handle_sigint(_: libc::c_int) {
    unsafe {
        QUIT_LOOP = true;
    }
}

fn setup_signal_handler() {
    let handler = SigHandler::Handler(handle_sigint);
    let _ = signal::signal(Signal::SIGINT, handler);
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: {} <veth-name> <cidr> <unix-socket>", args[0]);
        process::exit(1);
    }

    let veth_name = &args[1];
    let cidr = &args[2];
    let unix_socket_path = &args[3];

    let mut veth = Veth::init(veth_name);
    veth.create_veth(cidr).map_err(|e| {
        eprintln!("Failed to create veth pair: {}", e);
        e
    })?;

    setup_signal_handler();

    println!("You can quit using Ctrl-C");
    run_proxy(&mut veth, unix_socket_path)?;

    Ok(())
}

fn run_proxy(veth: &mut Veth, unix_socket_path: &str) -> io::Result<()> {
    // Setup raw socket (AF_PACKET)
    let peer_mac = veth.get_peer_mac()?;
    let peer_ifindex = veth.get_peer_ifindex()?;
    let peer_sockfd = setup_raw_socket(peer_mac, peer_ifindex)?;

    // Setup Unix socket
    let server_sockfd = setup_unix_socket(unix_socket_path)?;

    // Main loop
    let mut stdin = io::stdin();
    let mut stdin_buffer = [0; 64];
    let mut prompt = "> ";

    loop {
        if unsafe { QUIT_LOOP } {
            break;
        }

        // Poll for events
        let mut pollfds = [
            PollFd::new(stdin.as_raw_fd(), PollFlags::POLLIN),
            PollFd::new(peer_sockfd, PollFlags::POLLIN),
        ];

        let ret = poll(&mut pollfds, 200)?; // 200ms timeout

        if ret == 0 {
            continue; // Timeout
        }

        let mut msg: Option<Vec<u8>> = None;

        if pollfds[0].revents().is_some() {
            // Read from stdin
            let n = stdin.read(&mut stdin_buffer)?;
            if n == 0 {
                break; // EOF
            }
            msg = Some(stdin_buffer[..n].to_vec());
        } else if pollfds[1].revents().is_some() {
            // Read from raw socket
            let mut frame_buf = [0u8; 1600];
            let n = unsafe {
                libc::read(
                    peer_sockfd,
                    frame_buf.as_mut_ptr() as *mut _,
                    frame_buf.len(),
                )
            };
            if n <= 0 {
                eprintln!("Failed to read from peer socket");
                continue;
            }
            msg = Some(frame_buf[..n as usize].to_vec());
        }

        // Process message
        if let Some(m) = msg {
            send_to_server(&m, server_sockfd)?;
            let response = receive_from_server(server_sockfd)?;
            println!("Server response: {:?}", response);
        }

        print!("{}", prompt);
        io::stdout().flush()?;
    }

    println!("Break out of the loop cleanly");
    Ok(())
}

fn setup_raw_socket(peer_mac: [u8; 6], ifindex: i32) -> io::Result<RawFd> {
    // Create raw socket
    let sockfd = socket::socket(
        AddressFamily::Packet,
        SockType::Raw,
        SockFlag::empty(),
        None,
    )?;

    // Set up sockaddr_ll
    let mut sockaddr = SockaddrLinkLayer {
        sll_family: AddressFamily::Packet as u16,
        sll_protocol: 0x0003, // ETH_P_ALL
        sll_ifindex: ifindex,
        sll_hatype: 0,
        sll_pkttype: libc::PACKET_BROADCAST as u8, // 3
        sll_halen: 6,
        sll_addr: [0; 8],
    };
    sockaddr.sll_addr[..6].copy_from_slice(&peer_mac);

    // Bind to interface
    socket::bind(sockfd, &SockAddr::LinkLayer(sockaddr))?;

    Ok(sockfd)
}

fn setup_unix_socket(unix_socket_path: &str) -> io::Result<RawFd> {
    // Create Unix socket
    let sockfd = socket::socket(
        AddressFamily::Unix,
        SockType::Stream,
        SockFlag::empty(),
        None,
    )?;

    // Connect to server
    let addr = SockaddrUnix::new(unix_socket_path)?;
    socket::connect(sockfd, &SockAddr::Unix(addr))?;

    Ok(sockfd)
}

fn send_to_server(msg: &[u8], sockfd: RawFd) -> io::Result<()> {
    // Send message size (4 bytes)
    let size = msg.len() as u32;
    let size_bytes = size.to_le_bytes();
    unsafe { libc::write(sockfd, size_bytes.as_ptr() as *const _, 4) }?;

    // Send message
    unsafe { libc::write(sockfd, msg.as_ptr() as *const _, msg.len()) }?;
    Ok(())
}

fn receive_from_server(sockfd: RawFd) -> io::Result<Vec<u8>> {
    // Read message size
    let mut size_bytes = [0u8; 4];
    unsafe { libc::read(sockfd, size_bytes.as_mut_ptr() as *mut _, 4) }?;
    let size = u32::from_le_bytes(size_bytes) as usize;

    // Read message
    let mut buffer = vec![0u8; size];
    unsafe { libc::read(sockfd, buffer.as_mut_ptr() as *mut _, size) }?;
    Ok(buffer)
}
