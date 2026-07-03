CC      = cc
CFLAGS  = -O2 -Wall
LDFLAGS = -framework IOKit -framework CoreFoundation
TARGET  = smc_helper

all: $(TARGET)

$(TARGET): smc_helper.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
