#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

int main(int, char **)
{
	static char const *str = "Hello!";

	/* create new file */
	int fd = open("/foobar", O_RDWR | O_CREAT);
	if (fd < 0) {
		printf("Error: Unable to create file '/foobar'.\n");
		return -1;
	}

	int ret = write(fd, str, strlen(str));
	if (ret < 0) {
		printf("Unable to write to file '/foobar'.\n");
		return -1;
	}

	close(fd);

	sleep(5);

	/* append some text */
	fd = open("/foobar", O_RDWR);
	if (fd < 0) {
		printf("Error: Unable to open file '/foobar' for writing.\n");
		return -1;
	}


	ret = lseek(fd, 0, SEEK_END);
	if (ret < 0) {
		printf("Unable to seek to end.\n");
		return -1;
	}

	/* overwrite file */
	ret = write(fd, str, strlen(str));

	close(fd);
	return 0;
}
