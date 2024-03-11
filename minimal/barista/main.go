package main

import (
	"barista.run"
	"barista.run/bar"
	"barista.run/modules/clock"
	"barista.run/modules/volume"
	"barista.run/modules/volume/alsa"
	"barista.run/outputs"
)

func main() {
	barista.Add(volume.New(alsa.DefaultMixer()).Output(func(v volume.Volume) bar.Output {
		if v.Mute {
			return outputs.Text(" Vol: muted ")
		}
		return outputs.Textf(" Vol: %2d%% ", v.Pct())
	}))

	barista.Add(clock.Local().OutputFormat(" Time: 15:04 "))

	panic(barista.Run())
}
