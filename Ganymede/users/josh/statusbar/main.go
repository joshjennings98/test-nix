package main

import (
	"os/exec"
	"strconv"
	"time"

	"barista.run"
	"barista.run/bar"
	"barista.run/base/click"
	"barista.run/colors"
	"barista.run/modules/battery"
	"barista.run/modules/clock"
	"barista.run/modules/cpuload"
	"barista.run/modules/funcs"
	"barista.run/modules/meminfo"
	"barista.run/modules/netinfo"
	"barista.run/modules/shell"
	"barista.run/modules/volume"
	"barista.run/modules/volume/alsa"
	"barista.run/outputs"
	"github.com/godbus/dbus/v5"
)

func main() {
	if conn, err := dbus.SessionBus(); err == nil {
		barista.Add(funcs.Every(time.Second, func(s bar.Sink) {
			obj := conn.Object("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2")
			metadataProps := obj.Call("org.freedesktop.DBus.Properties.Get", 0, "org.mpris.MediaPlayer2.Player", "Metadata")
			if metadataProps.Err != nil {
				s.Output(nil)
				return
			}

			metadata := metadataProps.Body[0].(dbus.Variant).Value().(map[string]dbus.Variant)

			artistStr := "No Artist"
			if artist, ok := metadata["xesam:artist"]; ok {
				if artistStrLst := artist.Value().([]string); len(artistStrLst) > 0 {
					artistStr = artistStrLst[0]
				}
			}

			titleStr := "No Title"
			if title, ok := metadata["xesam:title"]; ok {
				if s := title.Value().(string); s != "" {
					titleStr = s
				}
			}

			playbackProps := obj.Call("org.freedesktop.DBus.Properties.Get", 0, "org.mpris.MediaPlayer2.Player", "PlaybackStatus")
			if metadataProps.Err != nil {
				s.Output(nil)
				return
			}

			playback := playbackProps.Body[0].(dbus.Variant).Value().(string)
			output := outputs.
				Textf(" %s - %s ", artistStr, titleStr).
				OnClick(func(e bar.Event) {
					switch {
					case e.Button == bar.ButtonLeft:
						obj.Call("org.mpris.MediaPlayer2.Player.PlayPause", 0)
					case e.Button == bar.ScrollUp:
						obj.Call("org.mpris.MediaPlayer2.Player.Next", 0)
					case e.Button == bar.ScrollDown:
						obj.Call("org.mpris.MediaPlayer2.Player.Previous", 0)
					default:
					}
				})

			if playback == "Paused" {
				output.Color(colors.Hex("#BBB"))
			}

			s.Output(output)
		}))
	}

	barista.Add(battery.All().Output(func(i battery.Info) bar.Output {
		if i.Status == battery.Disconnected || i.Status == battery.Unknown || i.EnergyFull == 0 {
			return nil
		}

		if i.Status == battery.Charging {
			return outputs.Textf(" Battery: %2d%% (charging)", i.RemainingPct())
		}

		var output *bar.Segment
		if i.RemainingPct() < 10 {
			output = outputs.Textf(" Battery: %1d%% ", i.RemainingPct())
		} else {
			output = outputs.Textf(" Battery: %2d%% ", i.RemainingPct())
		}

		if i.RemainingPct() < 20 {
			output.Color(colors.Hex("#F00"))
		}

		return output
	}))

	barista.Add(meminfo.New().Output(func(i meminfo.Info) bar.Output {
		memused := i["MemTotal"].Megabytes() - i["MemFree"].Megabytes() - i["Cached"].Megabytes() - i["Buffers"].Megabytes()
		return outputs.
			Textf(" Memory: %.0f MB (%.0f%%) ", memused, 100*memused/i["MemTotal"].Megabytes()).
			OnClick(click.RunLeft("kitty", "-e", "htop", "-s", "PERCENT_MEM"))
	}))

	barista.Add(cpuload.New().Output(func(l cpuload.LoadAvg) bar.Output {
		return outputs.
			Textf(" CPU Load: %0.2f ", l.Min1()).
			OnClick(click.RunLeft("kitty", "-e", "htop", "-s", "PERCENT_CPU"))
	}))

	barista.Add(shell.New("nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader").Every(1 * time.Second).Output(func(s string) bar.Output {
		output := outputs.
			Textf(" GPU Temp: %s °C", s).
			OnClick(click.RunLeft("kitty", "-e", "watch", "-n", "1", "nvidia-smi"))

		if i, err := strconv.Atoi(s); err == nil && i > 70 {
			output = output.Color(colors.Hex("#F00"))
		}

		return output
	}))

	barista.Add(netinfo.New().Output(func(s netinfo.State) bar.Output {
		if len(s.IPs) < 1 {
			return outputs.
				Text(" Network: Down ").
				Color(colors.Hex("#F00")).
				OnClick(click.RunLeft("kitty", "-e", "nmtui"))
		}
		return outputs.
			Text(" Network: Up ").
			OnClick(click.RunLeft("kitty", "-e", "nmtui"))
	}))

	barista.Add(volume.New(alsa.DefaultMixer()).Output(func(v volume.Volume) bar.Output {
		var output *bar.Segment

		if v.Mute {
			output = outputs.Text(" Volume: muted ")
		} else {
			output = outputs.Textf(" Volume: %2d%% ", v.Pct())
		}

		// Default click handler for volume only has mute on left click, this adds exec on right click
		return output.OnClick(func(e bar.Event) {
			if !volume.RateLimiter.Allow() {
				return
			}

			volStep := (v.Max - v.Min) / 100
			if volStep == 0 {
				volStep = 1
			}
			volStep = volStep * 5

			switch {
			case e.Button == bar.ButtonLeft:
				v.SetMuted(!v.Mute)
			case e.Button == bar.ButtonRight:
				exec.Command("pavucontrol").Run()
			case e.Button == bar.ScrollUp:
				v.SetVolume(v.Vol + volStep)
			case e.Button == bar.ScrollDown:
				v.SetVolume(v.Vol - volStep)
			default:
			}
		})

	}))

	localTime, _ := time.LoadLocation("Europe/London")

	barista.Add(clock.Local().Timezone(localTime).Output(
		10*time.Second,
		func(t time.Time) bar.Output {
			return outputs.
				Text(t.Format(" Time: 15:04 ")).
				OnClick(click.RunLeft("i3-nagbar", "-t", "warning", "-m", "Do you want to reboot or shutdown?", "-b", "shutdown", "i3-msg exec shutdown 0", "-b", "reboot", "i3-msg exec reboot"))
		}))

	panic(barista.Run())
}
