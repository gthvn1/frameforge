// It uses serde, serde_json
//
use serde::{Deserialize, Deserializer};
use std::io::{self, Read};
use std::process::{Command, Stdio};

#[derive(Debug, Deserialize)]
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

        let mut child = Command::new(cmd[0])
            .args(&cmd[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        let mut stdout = child.stdout.take().unwrap();
        let mut stderr = child.stderr.take().unwrap();

        stdout.read_to_end(&mut self.stdout)?;
        stderr.read_to_end(&mut self.stderr)?;

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

        let json_str = std::str::from_utf8(&self.stdout).map_err(|_| {
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
