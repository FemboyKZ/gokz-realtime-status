#include "extension.h"

CSMExtension g_SMExtension;
SMEXT_LINK(&g_SMExtension);

bool CSMExtension::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
    return true;
}

void CSMExtension::SDK_OnAllLoaded()
{
}

void CSMExtension::SDK_OnUnload()
{
}
