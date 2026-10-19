#import <Foundation/Foundation.h>

// The general pasteboard's text ("" if none) / replace it with `text`. Any thread.
NSString *SAClipboardGet(void);
void SAClipboardSet(NSString *text);

// Types `text` into the focused field: pasteboard + Cmd+V. The text stays on the pasteboard: iOS asks
// "Allow Paste" for an injected paste, and changing the pasteboard again would dismiss that prompt.
BOOL SAText(NSString *text);
