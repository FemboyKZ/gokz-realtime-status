/**
 * FKZ API - Config loading
 *
 * Reads addons/sourcemod/configs/fkz-api.cfg (key "value" pairs).
 */

void LoadConfig()
{
    char cfgPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/fkz-api.cfg");

    File file = OpenFile(cfgPath, "r");
    if (file == null)
    {
        LogError("[FKZ] Config not found: %s", cfgPath);
        return;
    }

    char line[512];
    while (file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);

        if (line[0] == '/' || line[0] == '#' || line[0] == '\0')
            continue;

        char key[64], value[256];
        if (ParseConfigLine(line, key, sizeof(key), value, sizeof(value)))
        {
            if (StrEqual(key, "api_url"))
                strcopy(g_apiUrl, sizeof(g_apiUrl), value);
            else if (StrEqual(key, "api_key"))
                strcopy(g_apiKey, sizeof(g_apiKey), value);
            else if (StrEqual(key, "server_ip"))
                strcopy(g_serverIp, sizeof(g_serverIp), value);
            else if (StrEqual(key, "server_port"))
                g_serverPort = StringToInt(value);
            else if (StrEqual(key, "tls_ca_file"))
                strcopy(g_tlsCAFile, sizeof(g_tlsCAFile), value);
            else if (StrEqual(key, "interval"))
            {
                g_interval = StringToFloat(value);
                if (g_interval < 1.0)
                    g_interval = 1.0;
            }
        }
    }

    delete file;

    // api_url is the API root (e.g. https://api.femboykz.com).
    // Drop any trailing slash so endpoint paths concatenate cleanly.
    int len = strlen(g_apiUrl);
    if (len > 0 && g_apiUrl[len - 1] == '/')
        g_apiUrl[len - 1] = '\0';
}

bool ParseConfigLine(const char[] line, char[] key, int keyLen, char[] value, int valueLen)
{
    int pos = 0;
    while (line[pos] == ' ' || line[pos] == '\t')
        pos++;

    if (line[pos] == '"')
    {
        pos++;
        int start = pos;
        while (line[pos] != '"' && line[pos] != '\0')
            pos++;
        int len = pos - start;
        if (len >= keyLen)
            len = keyLen - 1;
        strcopy(key, len + 1, line[start]);
        if (line[pos] == '"')
            pos++;
    }
    else
    {
        int start = pos;
        while (line[pos] != ' ' && line[pos] != '\t' && line[pos] != '\0')
            pos++;
        int len = pos - start;
        if (len >= keyLen)
            len = keyLen - 1;
        strcopy(key, len + 1, line[start]);
    }

    while (line[pos] == ' ' || line[pos] == '\t')
        pos++;

    if (line[pos] == '"')
    {
        pos++;
        int start = pos;
        while (line[pos] != '"' && line[pos] != '\0')
            pos++;
        int len = pos - start;
        if (len >= valueLen)
            len = valueLen - 1;
        strcopy(value, len + 1, line[start]);
        return true;
    }

    return false;
}
