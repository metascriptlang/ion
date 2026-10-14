
#import "../state.h"
#import "../../bridge.h"

void ionWebviewEval(IonWebviewId id, const char *js) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    if (!st || js == NULL) return;
    [st->view evaluateJavaScript:[NSString stringWithUTF8String:js] completionHandler:nil];
}

void ionWebviewNavigate(IonWebviewId id, const char *url) {
    IonMacWebviewState *st = ionMacWebviewState(id);
    if (!st || url == NULL || url[0] == '\0') return;
    NSURL *nsURL = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
    if (nsURL != nil) [st->view loadRequest:[NSURLRequest requestWithURL:nsURL]];
}
