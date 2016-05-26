#
# Copyright (C) 2013,2014,2015,2016 The ESPResSo project
#
# This file is part of ESPResSo.
#
# ESPResSo is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ESPResSo is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
from __future__ import print_function
import espressomd._system as es
import espressomd
from espressomd import thermostat
from espressomd import analyze
from espressomd import integrate
from espressomd import visualization
import numpy
from matplotlib import pyplot
from threading import Thread
from traits.api import HasTraits, Button, Any, Range, List
from traitsui.api import View, Group, Item, CheckListEditor
from pygame import midi

midi.init()

# System parameters
#############################################################

# 10 000  Particles
box_l = 10.7437
density = 0.7

# Interaction parameters (repulsive Lennard Jones)
#############################################################

lj_eps = 1.0
lj_sig = 1.0
lj_cut = 1.12246
lj_cap = 20

# Integration parameters
#############################################################
system = espressomd.System()
system.time_step = 0.01
system.skin = 0.4
system.thermostat.set_langevin(kT=1.0, gamma=1.0)

# warmup integration (with capped LJ potential)
warm_steps = 100
warm_n_times = 30
# do the warmup until the particles have at least the distance min__dist
min_dist = 0.9

# integration
int_steps = 1000
int_n_times = 50000


#############################################################
#  Setup System                                             #
#############################################################

# Interaction setup
#############################################################

system.box_l = [box_l, box_l, box_l]

system.non_bonded_inter[0, 0].lennard_jones.set_params(
    epsilon=lj_eps, sigma=lj_sig,
    cutoff=lj_cut, shift="auto")
system.non_bonded_inter.set_force_cap(lj_cap)

# Particle setup
#############################################################

volume = box_l * box_l * box_l
n_part = int(volume * density)

for i in range(n_part):
    system.part.add(id=i, pos=numpy.random.random(3) * system.box_l)

analyze.distto(system, 0)

act_min_dist = analyze.mindist(system)
system.max_num_cells = 2744

mayavi = visualization.mayavi_live(system)

#############################################################
#  GUI Controls                                            #
#############################################################

inputs, outputs = [],[]
for i in range(midi.get_count()):
	interf, name, input, output, opened = midi.get_device_info(i)
	if input:
		inputs.append((i, interf + " " + name))
	if output:
		outputs.append((i, interf + " " + name))

class Controls(HasTraits):
	inputdevice = List(editor=CheckListEditor(values=inputs))
	outputdevice = List(editor=CheckListEditor(values=outputs))
	temperature = Range(0., 5., 1., )
	volume = Range(0., 2., 1., )
	pressure = Range(0., 2., 1., )
	particlenumber = Range(0, 20000, 10000, )
	
	midi_input = midi.Input(inputs[0][0])
	midi_output = midi.Output(outputs[0][0])
	
	MIDI_CC = 176
	MIDI_BASE = 81
	MIDI_NUM_TEMPERATURE = MIDI_BASE+0
	
	_ui = Any
	view = View(Group(Item('inputdevice'), Item('outputdevice'), show_labels=True),
	            Group(Item('temperature'), Item('volume'), Item('pressure'), Item('particlenumber'), show_labels=True),
	            buttons=[], title='Simulation Parameters')
	
	def __init__(self, **traits):
		super(Controls, self).__init__(**traits)
		self._ui = self.edit_traits()
	
	def _inputdevice_fired(self):
		self.midi_input.close()
		self.midi_input = midi.Input(self.inputdevice[0])
	
	def _outputdevice_fired(self):
		self.midi_output.close()
		self.midi_output = midi.Output(self.outputdevice[0])
	
	def _temperature_fired(self):
		status=self.MIDI_CC
		data1=self.MIDI_NUM_TEMPERATURE
		data2=int(self.temperature/5*127)
		self.midi_output.write_short(status,data1,data2)

#############################################################
#  Warmup Integration                                       #
#############################################################

# set LJ cap
lj_cap = 20
system.non_bonded_inter.set_force_cap(lj_cap)

# Warmup Integration Loop
i = 0
while (i < warm_n_times and act_min_dist < min_dist):
    integrate.integrate(warm_steps)
    # Warmup criterion
    act_min_dist = analyze.mindist(system)
    i += 1

#   Increase LJ cap
    lj_cap = lj_cap + 10
    system.non_bonded_inter.set_force_cap(lj_cap)
    mayavi.update()

#############################################################
#      Integration                                          #
#############################################################

# remove force capping
lj_cap = 0
system.non_bonded_inter.set_force_cap(lj_cap)

# print initial energies
energies = analyze.energy(system=system)

plot, = pyplot.plot([0],[energies['total']], label="total")
pyplot.xlabel("Time")
pyplot.ylabel("Energy")
pyplot.legend()
pyplot.show(block=False)

j = 0

def main_loop():
    global energies

    integrate.integrate(int_steps)
    system.thermostat.set_langevin(kT=controls.temperature, gamma=1.0)
    mayavi.update()

    energies = analyze.energy(system=system)
    plot.set_xdata(numpy.append(plot.get_xdata(), system.time))
    plot.set_ydata(numpy.append(plot.get_ydata(), energies['total']))
    linear_momentum = analyze.analyze_linear_momentum(system=system)

def main_thread():
    for i in range(0, int_n_times):
        main_loop()

def midi_thread():
	while True:
		try:
			if controls.midi_input.poll():
				events = controls.midi_input.read(1000)
				for event in events:
					status,data1,data2,data3 = event[0]
					if status == controls.MIDI_CC and data1 == controls.MIDI_NUM_TEMPERATURE:
						temperature = data2 * 5.0 / 127
						controls.temperature = temperature
		except Exception as e:
			print (e)

last_plotted = 0
def update_plot():
    global last_plotted
    current_time = plot.get_xdata()[-1]
    if last_plotted == current_time:
        return
    last_plotted = current_time
    pyplot.xlim(0, plot.get_xdata()[-1])
    pyplot.ylim(plot.get_ydata().min(), plot.get_ydata().max())
    pyplot.draw()

t = Thread(target=main_thread)
t.daemon = True
mayavi.register_callback(update_plot, interval=2000)
controls = Controls()
t.start()
t2 = Thread(target=midi_thread)
t2.daemon = True
t2.start()
mayavi.run_gui_event_loop()
