#import <Foundation/Foundation.h>

// The general pasteboard's text ("" if none), or nil if it can't be read within 30 s. Not on the main thread.
NSString *CTClipboardGet(void);
// Replaces the general pasteboard with `text`. Any thread.
void CTClipboardSet(NSString *text);

// Types `text` into the focused field: pasteboard + Cmd+V. The text stays on the pasteboard: iOS asks
// "Allow Paste" for an injected paste, and changing the pasteboard again would dismiss that prompt.
BOOL CTText(NSString *text);
