#import <Foundation/Foundation.h>

#define SA_PORT 7330

// Starts the 127.0.0.1:SA_PORT listener on its own thread. Safe to call once.
void SAServerStart(void);
