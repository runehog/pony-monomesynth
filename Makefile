.PHONY: all stable-deps clean

all: pony-monomesynth

stable-deps: bundle.json
	stable fetch

pony-monomesynth: stable-deps libportaudiosink.a *.pony
	stable env ponyc -p . -d

libportaudiosink.a: portaudio_sink.o
	ar -r libportaudio_sink.a portaudio_sink.o

portaudio_sink.o: portaudio_sink.c
	gcc -O3 -c portaudio_sink.c

clean:
	rm *.o pony-monomesynth
