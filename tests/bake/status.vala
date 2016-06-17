public static void report_status (string[] args) {
	var status_socket_name = Environment.get_variable ("BAKE_TEST_STATUS_SOCKET");
	if (status_socket_name == null) {
		stderr.printf ("BAKE_TEST_STATUS_SOCKET not defined\n");
		return;
	}
	Socket socket;
	try {
		socket = new Socket (SocketFamily.UNIX, SocketType.DATAGRAM, SocketProtocol.DEFAULT);
		socket.connect (new UnixSocketAddress (status_socket_name));
	} catch (Error e) {
		stderr.printf ("Failed to open status socket: %s\n", e.message);
		return;
	}
	var message = "%s\n".printf (string.joinv (" ", args));
	try {
		socket.send (message.data);
	} catch (Error e) {
		stderr.printf ("Failed to write to status socket: %s\n", e.message);
	}
}
