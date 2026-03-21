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

// Perform a blocking HTTP POST with JSON body. Returns HTTP status code, or -1 on error.
int HttpPostJson(const std::string &url, const std::string &json, const std::string &authKey = "");

#endif // _INCLUDE_HTTP_CLIENT_H_
