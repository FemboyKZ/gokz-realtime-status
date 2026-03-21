#ifndef _INCLUDE_HTTP_CLIENT_H_
#define _INCLUDE_HTTP_CLIENT_H_

#include <string>

struct HttpUrl
{
	std::string host;
	std::string path;
	int port;
	bool valid;
};

// Parse a URL like "http://host:port/path" into components
HttpUrl ParseUrl(const std::string &url);

// Error codes for HttpPostJson (negative values)
#define HTTP_ERR_INVALID_URL   (-1)
#define HTTP_ERR_DNS_FAILED    (-2)
#define HTTP_ERR_SOCKET_FAILED (-3)
#define HTTP_ERR_CONNECT_FAILED (-4)
#define HTTP_ERR_SEND_FAILED   (-5)
#define HTTP_ERR_RECV_FAILED   (-6)
#define HTTP_ERR_PARSE_FAILED  (-7)

// Perform a blocking HTTP POST with JSON body.
// Returns HTTP status code (>0) on success, or HTTP_ERR_* codes (<0) on error.
int HttpPostJson(const std::string &url, const std::string &json, const std::string &authKey = "");

#endif // _INCLUDE_HTTP_CLIENT_H_
