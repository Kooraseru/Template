/* source/main.c: shared application code; host identity is injected by its host. */
#include <stdio.h>

#ifndef HOST_MESSAGE
#error "Host implementation must supply HOST_MESSAGE"
#endif

int main(void)
{
    puts("Hello from the shared C application!");
    puts(HOST_MESSAGE);
    return 0;
}
