BIN=encrypt

all: build

build:
	nvcc -O3 -DNDEBUG -o $(BIN) encrypt_cuda.cu encrypt.cpp encrypt_cuda.cpp main.cpp

run: build
	./$(BIN) encrypted.txt decrypted.txt PDS_PDS_PDS_PDS decrypt

clean:
	rm $(BIN)
