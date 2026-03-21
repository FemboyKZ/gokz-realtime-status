#include "http_client.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
typedef SOCKET socket_t;
#define SOCKET_ERROR_VAL SOCKET_ERROR
#define INVALID_SOCK INVALID_SOCKET
#define CLOSE_SOCKET closesocket
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>
typedef int socket_t;
#define SOCKET_ERROR_VAL (-1)
#define INVALID_SOCK (-1)
#define CLOSE_SOCKET close
#endif

#include <cstring>
#include <cstdio>
#include <string>

HttpUrl ParseUrl(const std::string &url)
{
	HttpUrl result;
	result.valid = false;
	result.port = 80;
	result.path = "/";

	std::string work = url;

	// Strip http://
	const char *httpPrefix = "http://";
	if (work.compare(0, 7, httpPrefix) == 0)
		work = work.substr(7);

	// Find path
	size_t pathPos = work.find('/');
	if (pathPos != std::string::npos)
	{
		result.path = work.substr(pathPos);
		work = work.substr(0, pathPos);
	}

	// Find port
	size_t colonPos = work.find(':');
	if (colonPos != std::string::npos)
	{
		result.port = atoi(work.substr(colonPos + 1).c_str());
		work = work.substr(0, colonPos);
	}

	result.host = work;
	result.valid = !result.host.empty() && result.port > 0 && result.port < 65536;
	return result;
}

#ifdef _WIN32
static bool g_wsaInitialized = false;
static void EnsureWsaInit()
{
	if (!g_wsaInitialized)
	{
		WSADATA wsaData;
		WSAStartup(MAKEWORD(2, 2), &wsaData);
		g_wsaInitialized = true;
	}
}
#endif

int HttpPostJson(const std::string &url, const std::string &json, const std::string &authKey)
{
#ifdef _WIN32
	EnsureWsaInit();
#endif

	HttpUrl parsed = ParseUrl(url);
	if (!parsed.valid)
		return HTTP_ERR_INVALID_URL;

	// Resolve host
	struct addrinfo hints, *res = nullptr;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_protocol = IPPROTO_TCP;

	char portStr[16];
	snprintf(portStr, sizeof(portStr), "%d", parsed.port);

	if (getaddrinfo(parsed.host.c_str(), portStr, &hints, &res) != 0 || !res)
		return HTTP_ERR_DNS_FAILED;

	socket_t sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
	if (sock == INVALID_SOCK)
	{
		freeaddrinfo(res);
		return HTTP_ERR_SOCKET_FAILED;
	}

	// Set 10 second timeouts
#ifdef _WIN32
	DWORD timeout = 10000;
	setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));
	setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char *)&timeout, sizeof(timeout));
#else
	struct timeval tv;
	tv.tv_sec = 10;
	tv.tv_usec = 0;
	setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#endif

	if (connect(sock, res->ai_addr, (int)res->ai_addrlen) == SOCKET_ERROR_VAL)
	{
		freeaddrinfo(res);
		CLOSE_SOCKET(sock);
		return HTTP_ERR_CONNECT_FAILED;
	}
	freeaddrinfo(res);

	// Build HTTP request
	char contentLength[32];
	snprintf(contentLength, sizeof(contentLength), "%u", (unsigned int)json.size());

	std::string request;
	request.reserve(512 + json.size());
	request += "POST ";
	request += parsed.path;
	request += " HTTP/1.1\r\n";
	request += "Host: ";
	request += parsed.host;
	request += "\r\n";
	request += "Content-Type: application/json\r\n";
	request += "Content-Length: ";
	request += contentLength;
	request += "\r\n";
	request += "Connection: close\r\n";

	if (!authKey.empty())
	{
		request += "Authorization: Bearer ";
		request += authKey;
		request += "\r\n";
	}

	request += "\r\n";
	request += json;

	// Send
	int totalSent = 0;
	int reqLen = (int)request.size();
	while (totalSent < reqLen)
	{
		int sent = send(sock, request.c_str() + totalSent, reqLen - totalSent, 0);
		if (sent <= 0)
		{
			CLOSE_SOCKET(sock);
			return HTTP_ERR_SEND_FAILED;
		}
		totalSent += sent;
	}

	// Read response (just enough to get status code)
	char buf[512];
	int received = recv(sock, buf, sizeof(buf) - 1, 0);
	CLOSE_SOCKET(sock);

	if (received <= 0)
		return HTTP_ERR_RECV_FAILED;

	buf[received] = '\0';

	// Parse "HTTP/1.x NNN"
	int statusCode = HTTP_ERR_PARSE_FAILED;
	if (strncmp(buf, "HTTP/", 5) == 0)
	{
		const char *space = strchr(buf, ' ');
		if (space)
			statusCode = atoi(space + 1);
	}

	return statusCode;
}
