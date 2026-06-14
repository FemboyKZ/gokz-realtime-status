/**
 * FKZ API - HTTP transport
 *
 * The low-level request client: 
 * builds a request against the configured API root (api_url), applies TLS/auth, and dispatches it by method.
 * Shared by the public natives and the status updater.
 */

/**
 * Builds and dispatches an async request against the configured API root.
 *
 * @param method   HTTP verb (GET/POST/PUT/PATCH/DELETE), case-insensitive.
 * @param path     Endpoint path, with or without a leading slash.
 * @param body     JSON body for POST/PUT/PATCH (null otherwise). Not freed.
 * @param rcb      Raw HTTP response callback.
 * @param value    Opaque value forwarded to the callback.
 * @return         True if the request was dispatched.
 */
bool FKZ_SendRequest(const char[] method, const char[] path, JSON body, ResponseCallback rcb, any value)
{
    if (g_apiUrl[0] == '\0')
    {
        LogError("[FKZ] API request: no api_url configured");
        return false;
    }

    char url[768];
    FormatEx(url, sizeof(url), "%s%s%s",
             g_apiUrl, (path[0] == '/') ? "" : "/", path);

    HttpRequest req    = new HttpRequest(url);
    req.Timeout        = 10000;
    req.FollowRedirect = false;

    if (g_tlsCAFile[0] != '\0')
        req.SetTLSCAFile(g_tlsCAFile);

    if (g_apiKey[0] != '\0')
        req.SetBearerAuth(g_apiKey);

    bool sent;
    if (StrEqual(method, "GET", false))
    {
        sent = req.Get(rcb, value);
    }
    else if (StrEqual(method, "DELETE", false))
    {
        sent = req.Delete(rcb, value);
    }
    else if (StrEqual(method, "POST", false) || StrEqual(method, "PUT", false) || StrEqual(method, "PATCH", false))
    {
        // PostJson/PutJson/PatchJson serialize the body synchronously.
        JSON sendBody = body;
        bool tempBody = false;
        if (sendBody == null)
        {
            sendBody = view_as<JSON>(new JSONObject());
            tempBody = true;
        }

        if (StrEqual(method, "POST", false))
            sent = req.PostJson(sendBody, rcb, value);
        else if (StrEqual(method, "PUT", false))
            sent = req.PutJson(sendBody, rcb, value);
        else
            sent = req.PatchJson(sendBody, rcb, value);

        if (tempBody)
            delete sendBody;
    }
    else
    {
        LogError("[FKZ] API request: unsupported method '%s'", method);
        delete req;
        return false;
    }

    if (!sent)
    {
        LogError("[FKZ] API request: dispatch failed for %s %s", method, url);
        delete req;
        return false;
    }

    return true;
}
