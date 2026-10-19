#include "protoRegHelper.h"
#include "../../src/platform/common/protoReg.h"
#include <stdlib.h>

int ionTestProtoStatus(const char *scheme, const char *rawPath) {
    unsigned char *body = NULL;
    size_t len = 0;
    const char *mime = NULL;
    int status = 0;
    if (ionProtoLookup(scheme, rawPath, &body, &len, &mime, &status) == IonProtoNoScheme) return -1;
    free(body);
    return status;
}
