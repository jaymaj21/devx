CXX ?= g++
CC  := gcc

CXXFLAGS ?= -std=c++17  -Wall -Wextra
CXXFLAGS += -g
CFLAGS   ?=  -Wall -Wextra
CFLAGS += -g

SRC_DIR := src

# Buddy sources to build from C/C++.
BUDDY_C_SRCS := \
	$(SRC_DIR)/buddy22/src/bddio.c \
	$(SRC_DIR)/buddy22/src/bddop.c \
	$(SRC_DIR)/buddy22/src/cache.c \
	$(SRC_DIR)/buddy22/src/fdd.c \
	$(SRC_DIR)/buddy22/src/imatrix.c \
	$(SRC_DIR)/buddy22/src/kernel.c \
	$(SRC_DIR)/buddy22/src/pairs.c \
	$(SRC_DIR)/buddy22/src/prime.c \
	$(SRC_DIR)/buddy22/src/reorder.c \
	$(SRC_DIR)/buddy22/src/tree.c \
	$(SRC_DIR)/buddy22/src/bvec.c

BUDDY_CPP_SRCS :=

# Prebuilt Buddy static library containing the C++ wrappers
BUDDY_LIB := $(SRC_DIR)/buddy22/src/libbdd.a

# Core greggle sources plus BDD-based relations and Buddy.
SRCS := $(wildcard $(SRC_DIR)/*.cpp) \
        $(wildcard $(SRC_DIR)/relations/*.cpp) \
        $(BUDDY_C_SRCS) $(BUDDY_CPP_SRCS)

OBJS := $(SRCS:.cpp=.o)
OBJS := $(OBJS:.c=.o)
OBJS := $(OBJS:.cxx=.o)

TARGET := greggle_demo.exe
QUERY_TOOL := greggle.exe
REGEX_DOT_TOOL := greggle_regex_to_dot.exe

# Include paths for original relations and Buddy.
CXXFLAGS += -I$(SRC_DIR)/relations -I$(SRC_DIR)/buddy22/src
CFLAGS   += -I$(SRC_DIR)/buddy22/src

.PHONY: all clean

DEMO_OBJS := $(filter-out src/query_tool_main.o src/regex_to_dot_main.o, $(OBJS))
QUERY_OBJS := $(filter-out src/main.o src/regex_to_dot_main.o, $(OBJS))
REGEX_DOT_OBJS := $(filter-out src/main.o src/query_tool_main.o, $(OBJS))

all: $(TARGET) $(QUERY_TOOL) $(REGEX_DOT_TOOL)

$(TARGET): $(DEMO_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(BUDDY_LIB)

$(QUERY_TOOL): $(QUERY_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(BUDDY_LIB)

$(REGEX_DOT_TOOL): $(REGEX_DOT_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(BUDDY_LIB)

$(SRC_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(SRC_DIR)/relations/%.o: $(SRC_DIR)/relations/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(SRC_DIR)/buddy22/src/%.o: $(SRC_DIR)/buddy22/src/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	$(RM) $(OBJS) $(TARGET) $(QUERY_TOOL) $(REGEX_DOT_TOOL)
