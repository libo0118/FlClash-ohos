use super::EventSink;
use std::io;

// Mobile loads the Core in-process; this keeps one set of bindings for every platform.
pub struct Server;

fn unsupported() -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        "IPC server is not available on this platform",
    )
}

impl Server {
    pub fn bind(_address: String) -> io::Result<Self> {
        Err(unsupported())
    }

    pub fn events(&self, _sink: EventSink) {}

    pub fn send(&self, _payload: &[u8]) -> io::Result<()> {
        Err(unsupported())
    }

    pub fn close(&self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_desktop_ipc_without_opening_a_socket() {
        let error = Server::bind(String::new()).err().unwrap();
        assert_eq!(error.kind(), io::ErrorKind::Unsupported);
        assert_eq!(
            error.to_string(),
            "IPC server is not available on this platform"
        );
        let server = Server;
        assert_eq!(
            server.send(b"request").unwrap_err().kind(),
            io::ErrorKind::Unsupported
        );
        server.events(Box::new(|_| panic!("unsupported IPC cannot emit events")));
        server.close();
        server.close();
    }
}
