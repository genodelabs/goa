#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

void _send(int const sd, char * ip)
{
	sockaddr_in const  addr { 0, AF_INET, htons(1234), inet_addr(ip) };
	sockaddr    const *paddr = reinterpret_cast<sockaddr const *>(&addr);

	static char const *msg = "Hi, there!";

	while (1) {
		ssize_t bytes = sendto(sd, msg, strlen(msg)+1, 0, paddr, sizeof(addr));
		printf("Sent message with %d bytes\n", bytes);
		sleep(2);
	}
}

void _recv(int const sd, char *)
{
	sockaddr_in const  addr { 0, AF_INET, htons(1234), { INADDR_ANY } };
	sockaddr    const *paddr = reinterpret_cast<sockaddr const *>(&addr);

	if (bind(sd, paddr, sizeof(addr)) < 0) {
		printf("bind failed\n");
		return;
	}

	static char buf[128];

	while (1) {
		ssize_t bytes = recvfrom(sd, buf, sizeof(buf), 0, nullptr, 0);
		if (bytes > 0)
			printf("Received message with: %s\n", buf);
		sleep(2);
	}
}

int main(int argc, char ** argv)
{
	int const sd = socket(AF_INET, SOCK_DGRAM, 0);
	if (sd == -1) return -1;

	if (argc < 2) {
		printf("Usage: (sendto|recvfrom) <peer-ip-addr>\n");
		return -1;
	}

	if (strcmp(argv[0], "sendto") == 0)
		_send(sd, argv[1]);
	else if (strcmp(argv[0], "recvfrom") == 0)
		_recv(sd, argv[1]);
	else {
		printf("Unknown argument '%s'\n", argv[0]);
		return -1;
	}
}
