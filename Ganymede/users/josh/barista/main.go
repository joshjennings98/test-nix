package main

import (
	"os/exec"
	"time"

	"barista.run"
	"barista.run/bar"
	"barista.run/base/click"
	"barista.run/colors"
	"barista.run/modules/clock"
	"barista.run/modules/cpuload"
	"barista.run/modules/meminfo"
	"barista.run/modules/netinfo"
	"barista.run/modules/shell"
	"barista.run/modules/volume"
	"barista.run/modules/volume/alsa"
	"barista.run/outputs"
)

// Default click handler for volume only has mute on left click, this adds exec on right click
func volumeClickHandler(v volume.Volume, cmd string, args ...string) func(bar.Event) {
	return func(e bar.Event) {
		if !volume.RateLimiter.Allow() {
			return
		}
		if e.Button == bar.ButtonLeft {
			v.SetMuted(!v.Mute)
			return
		}
		if e.Button == bar.ButtonRight {
			exec.Command(cmd, args...).Run()
			return
		}
		volStep := (v.Max - v.Min) / 100
		if volStep == 0 {
			volStep = 1
		}
		volStep = volStep * 5
		if e.Button == bar.ScrollUp {
			v.SetVolume(v.Vol + volStep)
		}
		if e.Button == bar.ScrollDown {
			v.SetVolume(v.Vol - volStep)
		}
	}
}

func main() {
	barista.Add(meminfo.New().Output(func(i meminfo.Info) bar.Output {
		memused := i["MemTotal"].Megabytes() - i["MemFree"].Megabytes() - i["Cached"].Megabytes() - i["Buffers"].Megabytes()
		return outputs.
			Textf(" Memory: %.0f MB (%.0f%%) ", memused, 100 * memused / i["MemTotal"].Megabytes()).
			OnClick(click.RunLeft("kitty", "-e", "htop", "-s", "PERCENT_MEM"))
	}))

	barista.Add(cpuload.New().Output(func(l cpuload.LoadAvg) bar.Output {
		return outputs.
			Textf(" CPU Load: %0.2f ", l.Min1()).
			OnClick(click.RunLeft("kitty", "-e", "htop", "-s", "PERCENT_CPU"))
	}))

	barista.Add(shell.New("nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader").Every(1 * time.Second).Output(func(s string) bar.Output {
		return outputs.
			Textf(" GPU Temp: %s °C", s).
			OnClick(click.RunLeft("kitty", "-e", "watch", "-n", "1", "nvidia-smi"))
	}))

	barista.Add(netinfo.New().Output(func(s netinfo.State) bar.Output {
		if len(s.IPs) < 1 {
			return outputs.
				Text(" Network: Down ").
				Color(colors.Scheme("bad")).
				OnClick(click.RunLeft("kitty", "-e", "nmtui"))
		}
		return outputs.
			Text(" Network: Up ").
			OnClick(click.RunLeft("kitty", "-e", "nmtui"))
	}))

	barista.Add(volume.New(alsa.DefaultMixer()).Output(func(v volume.Volume) bar.Output {
		if v.Mute {
			return outputs.
				Text(" Volume: muted ").OnClick(volumeClickHandler(v, "pavucontrol"))
		}
		return outputs.
			Textf(" Volume: %2d%% ", v.Pct()).OnClick(volumeClickHandler(v, "pavucontrol"))
	}))

	barista.Add(clock.Local().OutputFormat(" Time: 15:04 "))

	panic(barista.Run())
}
