#include <stdio.h>
#include <windows.h>
#include <direct.h>

int main(int argc, char **argv) {
    char cwd[1024];
    if (_getcwd(cwd, sizeof(cwd)) != NULL) {
        printf("MOCK_CWD: %s\n", cwd);
    }
    for (int i = 0; i < argc; i++) {
        printf("MOCK_ARG[%d]: %s\n", i, argv[i]);
    }
    DWORD drives = GetLogicalDrives();
    for (char l = 'A'; l <= 'Z'; l++) {
        if (drives & (1 << (l - 'A'))) {
            printf("DRIVE_%c: present\n", l);
        }
    }
    return 0;
}
