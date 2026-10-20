#import <Foundation/Foundation.h>

#define CT_PORT 7330

// Starts the 127.0.0.1:CT_PORT listener on its own thread. Safe to call once.
void CTServerStart(void);
