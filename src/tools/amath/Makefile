CC = gcc
PREFIX = /usr/local
BUILD = build
SRC = src
TEST = test
LUA_INC ?= /usr/include/lua5.4
CFLAGS = -Wall -ansi -g -D _GNU_SOURCE -fPIC -O3
BINARY = $(BUILD)/amath
LIBRARY = $(BUILD)/libamath.so
LUA_LIBRARY = $(BUILD)/luaamath.so
SOURCES = $(SRC)/amath.c $(SRC)/main.c $(SRC)/util.c
OBJECTS = $(BUILD)/amath.o $(BUILD)/main.o $(BUILD)/util.o
LUA_OBJECTS = $(BUILD)/luaamath.o $(BUILD)/amath.o $(BUILD)/util.o
UNITS = "https://raw.githubusercontent.com/asciimath/asciimathml/master/test/unittests.js"

# phony targets

.PHONY: all otest test memory install uninstall clean

all: $(LIBRARY) $(LUA_LIBRARY) $(BINARY)

test: $(BINARY)
	@bash $(TEST)/test.sh

otest: $(BINARY) $(TEST)/unittests.js
	@perl -n $(TEST)/otest.pl $(TEST)/unittests.js

memory: $(BINARY)
	@bash $(TEST)/memory.sh

install: all
	install -m 0755 $(BINARY) $(PREFIX)/bin
	install -m 0755 $(LIBRARY) $(PREFIX)/lib
	install -m 0644 $(SRC)/amath.h $(PREFIX)/include

uninstall:
	rm -f $(PREFIX)/bin/amath
	rm -f $(PREFIX)/lib/libamath.so
	rm -f $(PREFIX)/include/amath.h

clean:
	rm -rf $(BUILD)

# binary and library

$(BINARY): $(OBJECTS)
	$(CC) -o $@ $^

$(LIBRARY): $(OBJECTS)
	$(CC) -shared -o $@ $(filter-out $(BUILD)/main.o, $^)

$(LUA_LIBRARY): $(LUA_OBJECTS)
	$(CC) -shared -o $@ $^

# object files

$(BUILD)/luaamath.o: luaamath.c | $(BUILD)
	$(CC) $(CFLAGS) -I$(SRC) -I$(LUA_INC) -c $< -o $@

$(BUILD)/%.o: $(SRC)/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD):
	mkdir -p $(BUILD)

# C dependencies

$(SRC)/amath.c: $(SRC)/amath.leg.c
	touch $@

$(SRC)/amath.leg.c: $(SRC)/amath.leg
	leg -o $@ $<

# test dependencies

$(TEST)/unittests.js:
	wget $(UNITS) -O $@

.SUFFIXES:
