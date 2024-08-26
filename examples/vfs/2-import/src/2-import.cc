#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

int main(int, char **)
{
	static char const *str = "Hello!";
	static char buf[128];

	/* try writing to immutable file */
	int fd = open("/tmp/static", O_RDWR);
	if (fd < 0) {
		printf("Error: Unable to open file '/tmp/static'.\n");
		return -1;
	}

	int ret = write(fd, str, strlen(str));
	if (ret < 0)
		printf("Unable to write to file '/tmp/static', this is expected.\n");
	else {
		printf("Unexpectedly written %d bytes to file '/tmp/static'.\n", ret);
		return -1;
	}

	close(fd);

	/* open existing file */
	fd = open("/tmp/x", O_RDWR | O_CREAT);
	if (fd < 0) {
		printf("Error: Unable to open file '/tmp/x' for writing.\n");
		return -1;
	}

	/* read file content */
	ret = read(fd, buf, sizeof(buf) - 1);
	printf("Read %d bytes from /tmp/x:\n%s\n", ret, buf);

	/* clear buffer after reading */
	memset(buf, 0, ret);

	/* truncate file */
	if (ret > 0) {
		ret = ftruncate(fd, 0);
		if (ret < 0) {
			printf("Unable to truncate file.\n");
			return -1;
		}

		ret = lseek(fd, 0, SEEK_SET);
		if (ret < 0) {
			printf("Unable to seek to beginning.\n");
			return -1;
		}
	}

	/* overwrite file */
	ret = write(fd, str, strlen(str));
	printf("Wrote %d bytes to /tmp/x\n", ret);

	/* read again */
	lseek(fd, 0, SEEK_SET);
	ret = read(fd, buf, sizeof(buf) - 1);
	printf("Read %d bytes from /tmp/x:\n%s\n", ret, buf);

	if (ret != strlen(str)) {
		printf("File is longer than expected\n");
		return -1;
	}

	close(fd);
	return 0;
}
