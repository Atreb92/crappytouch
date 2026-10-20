#import <Foundation/Foundation.h>

// While the "Keep Awake While Connected" switch (Settings › crappytouch) is on and at least one
// authenticated computer is connected, the phone doesn't auto-lock. Any thread.
void CTAwakeConnected(void);
void CTAwakeDisconnected(void);
