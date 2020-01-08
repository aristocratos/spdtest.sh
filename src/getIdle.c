#include <X11/extensions/scrnsaver.h>
#include <stdio.h>
/*
 * print X Server idle time in seconds
 * Compile: gcc -o ../getIdle getIdle.c -lXss -lX11
*/
int main(void) {
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        return(1);
    }
    XScreenSaverInfo *info = XScreenSaverAllocInfo();
    XScreenSaverQueryInfo(dpy, DefaultRootWindow(dpy), info);
    int sec = ((info->idle + 500) / 1000);
    printf("%u\n", sec);
    return(0);
}