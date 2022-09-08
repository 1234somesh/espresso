#
# Copyright (C) 2013-2022 The ESPResSo project
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
from libcpp.string cimport string
cimport cpython.object
import collections

include "myconfig.pxi"
from . import utils
from .script_interface import ScriptObjectMap, ScriptInterfaceHelper, script_interface_register


cdef class NonBondedInteraction:
    """
    Represents an instance of a non-bonded interaction, such as Lennard-Jones.
    Either called with two particle type id, in which case, the interaction
    will represent the bonded interaction as it is defined in ESPResSo core,
    or called with keyword arguments describing a new interaction.

    """

    cdef public object _part_types
    cdef public object _params

    # init dict to access all user defined nonbonded-inters via
    # user_interactions[type1][type2][parameter]
    cdef public object user_interactions

    def __init__(self, *args, **kwargs):
        if self.user_interactions is None:
            self.user_interactions = {}
        # Interaction id as argument
        if len(args) == 2 and utils.is_valid_type(
                args[0], int) and utils.is_valid_type(args[1], int):
            self._part_types = args

            # Load the parameters currently set in the ESPResSo core
            self._params = self._get_params_from_es_core()

        # Or have we been called with keyword args describing the interaction
        elif len(args) == 0:
            utils.check_required_keys(self.required_keys(), kwargs.keys())
            utils.check_valid_keys(self.valid_keys(), kwargs.keys())
            # Initialize default values
            self._params = self.default_params()
            self._part_types = [-1, -1]
            self._params.update(kwargs)
            self.validate_params()
        else:
            raise Exception(
                "The constructor has to be called either with two particle type ids (as integer), or with a set of keyword arguments describing a new interaction")

    def is_valid(self):
        """Check, if the data stored in the instance still matches what is in ESPResSo.

        """
        temp_params = self._get_params_from_es_core()
        return self._params == temp_params

    def get_params(self):
        """Get interaction parameters.

        """
        # If this instance refers to an actual interaction defined in
        # the es core, load current parameters from there
        if self._part_types[0] >= 0 and self._part_types[1] >= 0:
            self._params = self._get_params_from_es_core()
        return self._params

    def __str__(self):
        return f'{self.__class__.__name__}({self.get_params()})'

    def __getstate__(self):
        odict = collections.OrderedDict()
        odict['user_interactions'] = self.user_interactions
        odict['_part_types'] = self._part_types
        odict['params'] = self.get_params()
        return odict

    def __setstate__(self, state):
        self.user_interactions = state['user_interactions']
        self._part_types = state['_part_types']
        self._params = state['params']

    def set_params(self, **p):
        """Update the given parameters.

        """
        # Check, if any key was passed, which is not known
        utils.check_valid_keys(self.valid_keys(), p.keys())

        # When an interaction is newly activated, all required keys must be
        # given
        if not self.is_active():
            utils.check_required_keys(self.required_keys(), p.keys())

        # If this instance refers to an interaction defined in the ESPResSo core,
        # load the parameters from there
        is_valid_ia = self._part_types[0] >= 0 and self._part_types[1] >= 0

        if is_valid_ia:
            self._params = self._get_params_from_es_core()

        # Put in values given by the user
        self._params.update(p)

        if is_valid_ia:
            self._set_params_in_es_core()

        # update interaction dict when user sets interaction
        if self._part_types[0] not in self.user_interactions:
            self.user_interactions[self._part_types[0]] = {}
        self.user_interactions[self._part_types[0]][self._part_types[1]] = {}
        new_params = self.get_params()
        for p_key in new_params:
            self.user_interactions[self._part_types[0]][
                self._part_types[1]][p_key] = new_params[p_key]
        self.user_interactions[self._part_types[0]][
            self._part_types[1]]['type_name'] = self.type_name()

        # defer exception (core and interface must always agree on parameters)
        if is_valid_ia:
            utils.handle_errors(f'setting {self.type_name()} raised an error')

    def validate_params(self):
        """Check that parameters are valid.

        """
        pass

    def __getattribute__(self, name):
        """Every time _set_params_in_es_core is called, the parameter dict is also updated.

        """
        attr = object.__getattribute__(self, name)
        if hasattr(
                attr, '__call__') and attr.__name__ == "_set_params_in_es_core":
            def sync_params(*args, **kwargs):
                result = attr(*args, **kwargs)
                self._params.update(self._get_params_from_es_core())
                return result
            return sync_params
        else:
            return attr

    def _get_params_from_es_core(self):
        raise Exception(
            "Subclasses of NonBondedInteraction must define the _get_params_from_es_core() method.")

    def _set_params_in_es_core(self):
        raise Exception(
            "Subclasses of NonBondedInteraction must define the _set_params_in_es_core() method.")

    def default_params(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the default_params() method.")

    def is_active(self):
        """Virtual method.

        """
        # If this instance refers to an actual interaction defined in
        # the es core, load current parameters from there
        if self._part_types[0] >= 0 and self._part_types[1] >= 0:
            self._params = self._get_params_from_es_core()
        raise Exception(
            "Subclasses of NonBondedInteraction must define the is_active() method.")

    def type_name(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the type_name() method.")

    def valid_keys(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the valid_keys() method.")

    def required_keys(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the required_keys() method.")


class NewNonBondedInteraction(ScriptInterfaceHelper):
    """
    Represents an instance of a non-bonded interaction, such as Lennard-Jones.

    """

    def __init__(self, **kwargs):
        if "sip" in kwargs:
            super().__init__(**kwargs)
        else:
            self._validate(params=kwargs, check_required=True)
            params = self.default_params()
            params.update(kwargs)
            super().__init__(**params)

    def __str__(self):
        return f'{self.__class__.__name__}({self.get_params()})'

    def _validate(self, params, check_required=False):
        # Check, if any key was passed, which is not known
        keys = {x for x in params.keys() if x != "_types"}
        utils.check_valid_keys(self.valid_keys(), keys)
        # When an interaction is newly activated, all required keys must be
        # given
        if check_required:
            utils.check_required_keys(self.required_keys(), params.keys())

    def set_params(self, **kwargs):
        """Update the given parameters.

        """
        self._validate(params=kwargs, check_required=not self.is_active())

        params = self.get_params()
        params.update(kwargs)

        err_msg = f"setting {self.type_name()} raised an error"
        self.call_method("set_params", handle_errors_message=err_msg, **params)

    def _serialize(self):
        return (self.__class__.__name__, self.get_params())

    def default_params(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the default_params() method.")

    def is_active(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the is_active() method.")

    def type_name(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the type_name() method.")

    def valid_keys(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the valid_keys() method.")

    def required_keys(self):
        """Virtual method.

        """
        raise Exception(
            "Subclasses of NonBondedInteraction must define the required_keys() method.")


IF LENNARD_JONES == 1:

    @script_interface_register
    class LennardJonesInteraction(NewNonBondedInteraction):
        """
        Standard 6-12 Lennard-Jones potential.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            epsilon : :obj:`float`
                Magnitude of the interaction.
            sigma : :obj:`float`
                Interaction length scale.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
            shift : :obj:`float` or :obj:`str` \{'auto'\}
                Constant shift of the potential. If ``'auto'``, a default value
                is computed from ``sigma`` and ``cutoff``. The LJ potential
                will be shifted by :math:`4\\epsilon\\cdot\\text{shift}`.
            offset : :obj:`float`, optional
                Offset distance of the interaction.
            min : :obj:`float`, optional
                Restricts the interaction to a minimal distance.

        """

        _so_name = "Interactions::InteractionLJ"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.epsilon > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"offset": 0., "min": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "LennardJones"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"epsilon", "sigma", "cutoff", "shift", "offset", "min"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"epsilon", "sigma", "cutoff", "shift"}

IF WCA == 1:

    @script_interface_register
    class WCAInteraction(NewNonBondedInteraction):
        """
        Standard 6-12 Weeks-Chandler-Andersen potential.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            epsilon : :obj:`float`
                Magnitude of the interaction.
            sigma : :obj:`float`
                Interaction length scale.

        """

        _so_name = "Interactions::InteractionWCA"

        def is_active(self):
            return self.epsilon > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "WCA"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"epsilon", "sigma"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"epsilon", "sigma"}

        @property
        def cutoff(self):
            return self.call_method("get_cutoff")

IF LENNARD_JONES_GENERIC == 1:

    @script_interface_register
    class GenericLennardJonesInteraction(NewNonBondedInteraction):
        """
        Generalized Lennard-Jones potential.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            epsilon : :obj:`float`
                Magnitude of the interaction.
            sigma : :obj:`float`
                Interaction length scale.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
            shift : :obj:`float` or :obj:`str` \{'auto'\}
                Constant shift of the potential. If ``'auto'``, a default value
                is computed from the other parameters. The LJ potential
                will be shifted by :math:`\\epsilon\\cdot\\text{shift}`.
            offset : :obj:`float`
                Offset distance of the interaction.
            e1 : :obj:`int`
                Exponent of the repulsion term.
            e2 : :obj:`int`
                Exponent of the attraction term.
            b1 : :obj:`float`
                Prefactor of the repulsion term.
            b2 : :obj:`float`
                Prefactor of the attraction term.
            delta : :obj:`float`, optional
                ``LJGEN_SOFTCORE`` parameter delta. Allows control over how
                smoothly the potential drops to zero as lambda approaches zero.
            lam : :obj:`float`, optional
                ``LJGEN_SOFTCORE`` parameter lambda. Tune the strength of the
                interaction.

        """

        _so_name = "Interactions::InteractionLJGen"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.epsilon > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            IF LJGEN_SOFTCORE:
                return {"delta": 0., "lam": 1.}
            ELSE:
                return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "GenericLennardJones"

        def valid_keys(self):
            """All parameters that can be set.

            """
            IF LJGEN_SOFTCORE:
                return {"epsilon", "sigma", "cutoff", "shift",
                        "offset", "e1", "e2", "b1", "b2", "delta", "lam"}
            ELSE:
                return {"epsilon", "sigma", "cutoff",
                        "shift", "offset", "e1", "e2", "b1", "b2"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"epsilon", "sigma", "cutoff",
                    "shift", "offset", "e1", "e2", "b1", "b2"}

IF LJCOS == 1:

    @script_interface_register
    class LennardJonesCosInteraction(NewNonBondedInteraction):
        """Lennard-Jones cosine interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            epsilon : :obj:`float`
                Magnitude of the interaction.
            sigma : :obj:`float`
                Interaction length scale.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
            offset : :obj:`float`, optional
                Offset distance of the interaction.
        """

        _so_name = "Interactions::InteractionLJcos"

        def is_active(self):
            """Check if interactions is active.

            """
            return self.epsilon > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"offset": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "LennardJonesCos"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"epsilon", "sigma", "cutoff", "offset"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"epsilon", "sigma", "cutoff"}

IF LJCOS2 == 1:

    @script_interface_register
    class LennardJonesCos2Interaction(NewNonBondedInteraction):
        """Second variant of the Lennard-Jones cosine interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            epsilon : :obj:`float`
                Magnitude of the interaction.
            sigma : :obj:`float`
                Interaction length scale.
            offset : :obj:`float`, optional
                Offset distance of the interaction.
            width : :obj:`float`
                Width of interaction.
        """

        _so_name = "Interactions::InteractionLJcos2"

        def is_active(self):
            """Check if interactions is active.

            """
            return self.epsilon > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"offset": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "LennardJonesCos2"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"epsilon", "sigma", "width", "offset"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"epsilon", "sigma", "width"}

        @property
        def cutoff(self):
            return self.call_method("get_cutoff")

IF HAT == 1:

    @script_interface_register
    class HatInteraction(NewNonBondedInteraction):
        """Hat interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            F_max : :obj:`float`
                Magnitude of the interaction.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.

        """

        _so_name = "Interactions::InteractionHat"

        def is_active(self):
            return self.F_max > 0.

        def default_params(self):
            return {}

        def type_name(self):
            return "Hat"

        def valid_keys(self):
            return {"F_max", "cutoff"}

        def required_keys(self):
            return {"F_max", "cutoff"}

IF GAY_BERNE:

    @script_interface_register
    class GayBerneInteraction(NewNonBondedInteraction):
        """Gay--Berne interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            eps : :obj:`float`
                Potential well depth.
            sig : :obj:`float`
                Interaction range.
            cut : :obj:`float`
                Cutoff distance of the interaction.
            k1 : :obj:`float` or :obj:`str`
                Molecular elongation.
            k2 : :obj:`float`, optional
                Ratio of the potential well depths for the side-by-side
                and end-to-end configurations.
            mu : :obj:`float`, optional
                Adjustable exponent.
            nu : :obj:`float`, optional
                Adjustable exponent.

        """

        _so_name = "Interactions::InteractionGayBerne"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.eps > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "GayBerne"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"eps", "sig", "cut", "k1", "k2", "mu", "nu"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"eps", "sig", "cut", "k1", "k2", "mu", "nu"}

IF TABULATED:

    @script_interface_register
    class TabulatedNonBonded(NewNonBondedInteraction):
        """Tabulated interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            min : :obj:`float`,
                The minimal interaction distance.
            max : :obj:`float`,
                The maximal interaction distance.
            energy: array_like of :obj:`float`
                The energy table.
            force: array_like of :obj:`float`
                The force table.

        """

        _so_name = "Interactions::InteractionTabulated"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.cutoff > 0

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of the potential.

            """
            return "Tabulated"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"min", "max", "energy", "force"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"min", "max", "energy", "force"}

        @property
        def cutoff(self):
            return self.call_method("get_cutoff")

IF DPD:

    @script_interface_register
    class DPDInteraction(NewNonBondedInteraction):
        """DPD interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            weight_function : :obj:`int`, \{0, 1\}
                The distance dependence of the parallel part,
                either 0 (constant) or 1 (linear)
            gamma : :obj:`float`
                Friction coefficient of the parallel part
            k : :obj:`float`
                Exponent in the modified weight function
            r_cut : :obj:`float`
                Cutoff of the parallel part
            trans_weight_function : :obj:`int`, \{0, 1\}
                The distance dependence of the orthogonal part,
                either 0 (constant) or 1 (linear)
            trans_gamma : :obj:`float`
                Friction coefficient of the orthogonal part
            trans_r_cut : :obj:`float`
                Cutoff of the orthogonal part

        """

        _so_name = "Interactions::InteractionDPD"

        def is_active(self):
            return self.r_cut > 0. or self.trans_r_cut > 0.

        def default_params(self):
            return {
                "weight_function": 0,
                "gamma": 0.0,
                "k": 1.0,
                "r_cut": -1.0,
                "trans_weight_function": 0,
                "trans_gamma": 0.0,
                "trans_r_cut": -1.0}

        def type_name(self):
            return "DPD"

        def valid_keys(self):
            return {"weight_function", "gamma", "k", "r_cut",
                    "trans_weight_function", "trans_gamma", "trans_r_cut"}

        def required_keys(self):
            return set()

IF SMOOTH_STEP == 1:

    @script_interface_register
    class SmoothStepInteraction(NewNonBondedInteraction):
        """Smooth step interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            d : :obj:`float`
                Short range repulsion parameter.
            n : :obj:`int`, optional
                Exponent of short range repulsion.
            eps : :obj:`float`
                Magnitude of the second (soft) repulsion.
            k0 : :obj:`float`, optional
                Exponential factor in second (soft) repulsion.
            sig : :obj:`float`, optional
                Length scale of second (soft) repulsion.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.

        """

        _so_name = "Interactions::InteractionSmoothStep"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.eps > 0. and self.sig > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"n": 10, "k0": 0., "sig": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "SmoothStep"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"d", "n", "eps", "k0", "sig", "cutoff"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"d", "eps", "cutoff"}

IF BMHTF_NACL == 1:

    @script_interface_register
    class BMHTFInteraction(NewNonBondedInteraction):
        """BMHTF interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            a : :obj:`float`
                Magnitude of exponential part of the interaction.
            b : :obj:`float`
                Exponential factor of the interaction.
            c : :obj:`float`
                Magnitude of the term decaying with the sixth power of r.
            d : :obj:`float`
                Magnitude of the term decaying with the eighth power of r.
            sig : :obj:`float`
                Shift in the exponent.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
        """

        _so_name = "Interactions::InteractionBMHTF"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.a > 0. and self.c > 0. and self.d > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "BMHTF"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"a", "b", "c", "d", "sig", "cutoff"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"a", "b", "c", "d", "sig", "cutoff"}

IF MORSE == 1:

    @script_interface_register
    class MorseInteraction(NewNonBondedInteraction):
        """Morse interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            eps : :obj:`float`
                The magnitude of the interaction.
            alpha : :obj:`float`
                Stiffness of the Morse interaction.
            rmin : :obj:`float`
                Distance of potential minimum
            cutoff : :obj:`float`, optional
                Cutoff distance of the interaction.
        """

        _so_name = "Interactions::InteractionMorse"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.eps > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"cutoff": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "Morse"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"eps", "alpha", "rmin", "cutoff"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"eps", "alpha", "rmin"}

IF BUCKINGHAM == 1:

    @script_interface_register
    class BuckinghamInteraction(NewNonBondedInteraction):
        """Buckingham interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            a : :obj:`float`
                Magnitude of the exponential part of the interaction.
            b : :obj:`float`, optional
                Exponent of the exponential part of the interaction.
            c : :obj:`float`
                Prefactor of term decaying with the sixth power of distance.
            d : :obj:`float`
                Prefactor of term decaying with the fourth power of distance.
            discont : :obj:`float`
                Distance below which the potential is linearly continued.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
            shift: :obj:`float`, optional
                Constant potential shift.
        """

        _so_name = "Interactions::InteractionBuckingham"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.a > 0. or self.b > 0. or self.d > 0. or self.shift > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"b": 0., "shift": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "Buckingham"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"a", "b", "c", "d", "discont", "cutoff", "shift"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"a", "c", "d", "discont", "cutoff"}

IF SOFT_SPHERE == 1:

    @script_interface_register
    class SoftSphereInteraction(NewNonBondedInteraction):
        """Soft sphere interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            a : :obj:`float`
                Magnitude of the interaction.
            n : :obj:`float`
                Exponent of the power law.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
            offset : :obj:`float`, optional
                Offset distance of the interaction.
        """

        _so_name = "Interactions::InteractionSoftSphere"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.a > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {"offset": 0.}

        def type_name(self):
            """Name of interaction type.

            """
            return "SoftSphere"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"a", "n", "cutoff", "offset"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"a", "n", "cutoff"}

IF HERTZIAN == 1:

    @script_interface_register
    class HertzianInteraction(NewNonBondedInteraction):
        """Hertzian interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            eps : :obj:`float`
                Magnitude of the interaction.
            sig : :obj:`float`
                Interaction length scale.
        """

        _so_name = "Interactions::InteractionHertzian"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.eps > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "Hertzian"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"eps", "sig"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"eps", "sig"}

IF GAUSSIAN == 1:

    @script_interface_register
    class GaussianInteraction(NewNonBondedInteraction):
        """Gaussian interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            eps : :obj:`float`
                Overlap energy epsilon.
            sig : :obj:`float`
                Variance sigma of the Gaussian interaction.
            cutoff : :obj:`float`
                Cutoff distance of the interaction.
        """

        _so_name = "Interactions::InteractionGaussian"

        def is_active(self):
            """Check if interaction is active.

            """
            return self.eps > 0.

        def default_params(self):
            """Python dictionary of default parameters.

            """
            return {}

        def type_name(self):
            """Name of interaction type.

            """
            return "Gaussian"

        def valid_keys(self):
            """All parameters that can be set.

            """
            return {"eps", "sig", "cutoff"}

        def required_keys(self):
            """Parameters that have to be set.

            """
            return {"eps", "sig", "cutoff"}

IF THOLE:

    @script_interface_register
    class TholeInteraction(NewNonBondedInteraction):
        """Thole interaction.

        Methods
        -------
        set_params()
            Set or update parameters for the interaction.
            Parameters marked as required become optional once the
            interaction has been activated for the first time;
            subsequent calls to this method update the existing values.

            Parameters
            ----------
            scaling_coeff : :obj:`float`
                The factor used in the Thole damping function between
                polarizable particles i and j. Usually calculated by
                the polarizabilities :math:`\\alpha_i`, :math:`\\alpha_j`
                and damping parameters :math:`a_i`, :math:`a_j` via
                :math:`s_{ij} = \\frac{(a_i+a_j)/2}{((\\alpha_i\\cdot\\alpha_j)^{1/2})^{1/3}}`
            q1q2: :obj:`float`
                Charge factor of the involved charges. Has to be set because
                it acts only on the portion of the Drude core charge that is
                associated to the dipole of the atom. For charged, polarizable
                atoms that charge is not equal to the particle charge property.
        """

        _so_name = "Interactions::InteractionThole"

        def is_active(self):
            return self.scaling_coeff != 0.

        def default_params(self):
            return {}

        def type_name(self):
            return "Thole"

        def valid_keys(self):
            return {"scaling_coeff", "q1q2"}

        def required_keys(self):
            return {"scaling_coeff", "q1q2"}


@script_interface_register
class NonBondedInteractionHandle(ScriptInterfaceHelper):

    """
    Provides access to all non-bonded interactions between two particle types.

    """
    _so_name = "Interactions::NonBondedInteractionHandle"

    def __getattr__(self, key):
        obj = super().__getattr__(key)
        return globals()[obj.__class__.__name__](
            _types=self.call_method("get_types"), **obj.get_params())

    def __init__(self, *args, **kwargs):
        if "sip" in kwargs:
            super().__init__(**kwargs)
            return
        if len(args):
            _type1, _type2 = args
        else:
            _type1, _type2 = kwargs.pop("_types")
        if not (utils.is_valid_type(_type1, int)
                and utils.is_valid_type(_type2, int)):
            raise TypeError("The particle types have to be of type integer.")
        super().__init__(_types=[_type1, _type2], **kwargs)

    def _serialize(self):
        serialized = []
        for name, obj in self.get_params().items():
            serialized.append((name, *obj._serialize()))
        return serialized


@script_interface_register
class NonBondedInteractions(ScriptInterfaceHelper):
    """
    Access to non-bonded interaction parameters via ``[i,j]``, where ``i, j``
    are particle types. Returns a :class:`NonBondedInteractionHandle` object.

    """
    _so_name = "Interactions::NonBondedInteractions"
    _so_creation_policy = "GLOBAL"
    # _so_bind_methods = ("reset",)

    def keys(self):
        return [tuple(x) for x in self.call_method("keys")]

    def _assert_key_type(self, key):
        if not isinstance(key, tuple) or len(key) != 2 or \
                not utils.is_valid_type(key[0], int) or not utils.is_valid_type(key[1], int):
            raise TypeError(
                "NonBondedInteractions[] expects two particle types as indices.")

    def __getitem__(self, key):
        self._assert_key_type(key)
        return NonBondedInteractionHandle(_types=key)

    def __setitem__(self, key, value):
        self._assert_key_type(key)
        self.call_method("insert", key=key, object=value)

    def __getstate__(self):
        cdef string core_state = ia_params_get_state()
        n_types = self.call_method("get_n_types")
        state = []
        for i in range(n_types):
            for j in range(i, n_types):
                handle = NonBondedInteractionHandle(_types=(i, j))
                state.append(((i, j), handle._serialize()))
        return {"state": state, "core_state": core_state}

    def __setstate__(self, params):
        for types, kwargs in params["state"]:
            objects = {}
            for name, class_name, obj_params in kwargs:
                objects[name] = globals()[class_name](**obj_params)
            obj = NonBondedInteractionHandle(_types=types, **objects)
            self.call_method("insert", key=types, object=obj)

    def reset(self):
        """
        Reset all interaction parameters to their default values.
        """
        reset_ia_params()
        self.call_method("reset")

    @classmethod
    def _restore_object(cls, so_callback, so_callback_args, state):
        cdef string core_state = state["core_state"]
        ia_params_set_state(core_state)
        so = so_callback(*so_callback_args)
        so.__setstate__(state)
        return so

    def __reduce__(self):
        so_callback, (so_name, so_bytestring) = super().__reduce__()
        return (NonBondedInteractions._restore_object,
                (so_callback, (so_name, so_bytestring), self.__getstate__()))


class BondedInteraction(ScriptInterfaceHelper):

    """
    Base class for bonded interactions.

    Either called with an interaction id, in which case the interaction
    will represent the bonded interaction as it is defined in ESPResSo core,
    or called with keyword arguments describing a new interaction.

    """

    _so_name = "Interactions::BondedInteraction"
    _so_creation_policy = "GLOBAL"

    def __init__(self, *args, **kwargs):
        if len(args) == 1 and len(kwargs) == 0 and isinstance(args[0], dict):
            # this branch is only visited by checkpointing constructor #2
            kwargs = args[0]
            args = []

        if not 'sip' in kwargs:
            if len(args) == 1 and utils.is_valid_type(args[0], int):
                # create a new script interface object for a bond that already
                # exists in the core via bond_id (checkpointing constructor #1)
                bond_id = args[0]
                # Check if the bond type in ESPResSo core matches this class
                if get_bonded_interaction_type_from_es_core(
                        bond_id) != self.type_number():
                    raise Exception(
                        f"The bond with id {bond_id} is not defined as a "
                        f"{self.type_name()} bond in the ESPResSo core.")
                super().__init__(bond_id=bond_id)
                self._bond_id = bond_id
                self._ctor_params = self._get_params_from_es_core()
            else:
                # create a bond from bond parameters
                params = self.get_default_params()
                params.update(kwargs)
                self.validate_params(params)
                super().__init__(*args, **params)
                utils.check_valid_keys(self.valid_keys(), kwargs.keys())
                self._ctor_params = params
                self._bond_id = -1
        else:
            # create a new bond based on a bond in the script interface
            # (checkpointing constructor #2 or BondedInteractions getter)
            super().__init__(**kwargs)
            self._bond_id = -1
            self._ctor_params = self._get_params_from_es_core()

    def __reduce__(self):
        if self._bond_id != -1:
            # checkpointing constructor #1
            return (self.__class__, (self._bond_id,))
        else:
            # checkpointing constructor #2
            return (self.__class__, (self._ctor_params,))

    def __setattr__(self, attr, value):
        super().__setattr__(attr, value)

    @property
    def params(self):
        return self._get_params_from_es_core()

    @params.setter
    def params(self, p):
        raise RuntimeError("Bond parameters are immutable.")

    def validate_params(self, params):
        """Check that parameters are valid.

        """
        pass

    def _get_params_from_es_core(self):
        return {key: getattr(self, key) for key in self.valid_keys()}

    def __str__(self):
        return f'{self.__class__.__name__}({self._ctor_params})'

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        raise Exception(
            "Subclasses of BondedInteraction must define the get_default_params() method.")

    def type_number(self):
        raise Exception(
            "Subclasses of BondedInteraction must define the type_number() method.")

    def type_name(self):
        """Name of interaction type.

        """
        raise Exception(
            "Subclasses of BondedInteraction must define the type_name() method.")

    def valid_keys(self):
        """All parameters that can be set.

        """
        return set(self._valid_parameters())

    def required_keys(self):
        """Parameters that have to be set.

        """
        return self.valid_keys().difference(self.get_default_params().keys())

    def __repr__(self):
        return f'<{self}>'

    def __eq__(self, other):
        return self.__richcmp__(other, cpython.object.Py_EQ)

    def __ne__(self, other):
        return self.__richcmp__(other, cpython.object.Py_NE)

    def __richcmp__(self, other, op):
        are_equal = self.__class__ == other.__class__ and self.call_method(
            "get_address") == other.call_method("get_address")
        if op == cpython.object.Py_EQ:
            return are_equal
        elif op == cpython.object.Py_NE:
            return not are_equal
        else:
            raise NotImplementedError("only equality comparison is supported")


class BondedInteractionNotDefined:

    def __init__(self, *args, **kwargs):
        raise Exception(
            self.__class__.__name__ + " not compiled into ESPResSo core")

    def type_number(self):
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def type_name(self):
        """Name of interaction type.

        """
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def valid_keys(self):
        """All parameters that can be set.

        """
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def required_keys(self):
        """Parameters that have to be set.

        """
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def _get_params_from_es_core(self):
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")

    def _set_params_in_es_core(self):
        raise Exception(f"{self.name} has to be defined in myconfig.hpp.")


@script_interface_register
class FeneBond(BondedInteraction):

    """
    FENE bond.

    Parameters
    ----------
    k : :obj:`float`
        Magnitude of the bond interaction.
    d_r_max : :obj:`float`
        Maximum stretch and compression length of the bond.
    r_0 : :obj:`float`, optional
        Equilibrium bond length.

    """

    _so_name = "Interactions::FeneBond"

    def type_number(self):
        return BONDED_IA_FENE

    def type_name(self):
        """Name of interaction type.

        """
        return "FENE"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {"r_0": 0.}


@script_interface_register
class HarmonicBond(BondedInteraction):

    """
    Harmonic bond.

    Parameters
    ----------
    k : :obj:`float`
        Magnitude of the bond interaction.
    r_0 : :obj:`float`
        Equilibrium bond length.
    r_cut : :obj:`float`, optional
        Maximum distance beyond which the bond is considered broken.

    """

    _so_name = "Interactions::HarmonicBond"

    def type_number(self):
        return BONDED_IA_HARMONIC

    def type_name(self):
        """Name of interaction type.

        """
        return "HARMONIC"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {"r_cut": 0.}


if ELECTROSTATICS:

    @script_interface_register
    class BondedCoulomb(BondedInteraction):

        """
        Bonded Coulomb bond.

        Parameters
        ----------

        prefactor : :obj:`float`
            Coulomb prefactor of the bonded Coulomb interaction.
        """

        _so_name = "Interactions::BondedCoulomb"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

        def type_number(self):
            return BONDED_IA_BONDED_COULOMB

        def type_name(self):
            return "BONDED_COULOMB"

        def get_default_params(self):
            """Gets default values of optional parameters.

            """
            return {}


if ELECTROSTATICS:

    @script_interface_register
    class BondedCoulombSRBond(BondedInteraction):

        """
        Bonded Coulomb short range bond. Calculates the short range part of
        Coulomb interactions.

        Parameters
        ----------

        q1q2 : :obj:`float`
            Charge factor of the involved particle pair. Note the
            particle charges are used to allow e.g. only partial subtraction
            of the involved charges.
        """

        _so_name = "Interactions::BondedCoulombSR"

        def type_number(self):
            return BONDED_IA_BONDED_COULOMB_SR

        def type_name(self):
            return "BONDED_COULOMB_SR"

        def get_default_params(self):
            return {}


@script_interface_register
class ThermalizedBond(BondedInteraction):

    """
    Thermalized bond.

    Parameters
    ----------

    temp_com : :obj:`float`
        Temperature of the Langevin thermostat for the center of mass of the
        particle pair.
    gamma_com: :obj:`float`
        Friction coefficient of the Langevin thermostat for the center of mass
        of the particle pair.
    temp_distance: :obj:`float`
        Temperature of the Langevin thermostat for the distance vector
        of the particle pair.
    gamma_distance: :obj:`float`
        Friction coefficient of the Langevin thermostat for the
        distance vector of the particle pair.
    r_cut: :obj:`float`, optional
        Maximum distance beyond which the bond is considered broken.
    seed : :obj:`int`
        Initial counter value (or seed) of the philox RNG.
        Required on the first thermalized bond in the system. Must be positive.
        If prompted, it does not return the initially set counter value
        (the seed) but the current state of the RNG.

    """

    _so_name = "Interactions::ThermalizedBond"

    def __init__(self, *args, **kwargs):
        counter = None
        # Interaction id as argument
        if len(args) == 2 and isinstance(args[0], (dict, int)):
            counter = args[1]
            args = (args[0],)
        super().__init__(*args, **kwargs)
        if counter is not None:
            thermalized_bond_set_rng_counter(counter)
        if self.params["seed"] is None and thermalized_bond.is_seed_required():
            raise ValueError(
                "A seed has to be given as keyword argument on first activation of the thermalized bond")

    def __reduce__(self):
        counter = thermalized_bond.rng_counter()
        if self._bond_id != -1:
            return (self.__class__, (self._bond_id, counter))
        else:
            return (self.__class__, (self._ctor_params, counter))

    def type_number(self):
        return BONDED_IA_THERMALIZED_DIST

    def type_name(self):
        return "THERMALIZED_DIST"

    def validate_params(self, params):
        if params["seed"] is not None:
            utils.check_type_or_throw_except(
                params["seed"], 1, int, "seed must be a positive integer")
            if params["seed"] < 0:
                raise ValueError("seed must be a positive integer")

    def get_default_params(self):
        return {"r_cut": 0., "seed": None}


IF BOND_CONSTRAINT == 1:

    @script_interface_register
    class RigidBond(BondedInteraction):

        """
        Rigid bond.

        Parameters
        ----------
        r : :obj:`float`
            Bond length.
        ptol : :obj:`float`, optional
            Tolerance for positional deviations.
        vtop : :obj:`float`, optional
            Tolerance for velocity deviations.

        """

        _so_name = "Interactions::RigidBond"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

        def type_number(self):
            return BONDED_IA_RIGID_BOND

        def type_name(self):
            """Name of interaction type.

            """
            return "RIGID"

        def get_default_params(self):
            """Gets default values of optional parameters.

            """
            # TODO rationality of Default Parameters has to be checked
            return {"ptol": 0.001, "vtol": 0.001}

ELSE:
    class RigidBond(BondedInteractionNotDefined):
        name = "RIGID"


@script_interface_register
class Dihedral(BondedInteraction):

    """
    Dihedral potential with phase shift.

    Parameters
    ----------
    mult : :obj:`int`
        Multiplicity of the potential (number of minima).
    bend : :obj:`float`
        Bending constant.
    phase : :obj:`float`
        Angle of the first local minimum in radians.

    """

    _so_name = "Interactions::DihedralBond"

    def type_number(self):
        return BONDED_IA_DIHEDRAL

    def type_name(self):
        """Name of interaction type.

        """
        return "DIHEDRAL"

    def validate_params(self, params):
        """Check that parameters are valid.

        """
        if params["mult"] is not None:
            utils.check_type_or_throw_except(
                params["mult"], 1, int, "mult must be a positive integer")

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


IF TABULATED:
    class _TabulatedBase(BondedInteraction):

        """
        Parent class for tabulated bonds.

        Parameters
        ----------

        min : :obj:`float`
            The minimal interaction distance. Has to be 0 for angles and dihedrals.
        max : :obj:`float`
            The maximal interaction distance. Has to be pi for angles and 2pi for
            dihedrals.
        energy: array_like of :obj:`float`
            The energy table.
        force: array_like of :obj:`float`
            The force table.

        """

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

        def type_number(self):
            return "BONDED_IA_TABULATED"

        def type_name(self):
            """Name of interaction type.

            """
            return "TABULATED_BOND"

        def get_default_params(self):
            """Gets default values of optional parameters.

            """
            return {}

    @script_interface_register
    class TabulatedDistance(_TabulatedBase):

        """
        Tabulated bond length.

        Parameters
        ----------

        min : :obj:`float`
            The minimal interaction distance.
        max : :obj:`float`
            The maximal interaction distance.
        energy: array_like of :obj:`float`
            The energy table.
        force: array_like of :obj:`float`
            The force table.

        """

        _so_name = "Interactions::TabulatedDistanceBond"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

        def type_number(self):
            return BONDED_IA_TABULATED_DISTANCE

        def type_name(self):
            """Name of interaction type.

            """
            return "TABULATED_DISTANCE"

    @script_interface_register
    class TabulatedAngle(_TabulatedBase):

        """
        Tabulated bond angle.

        Parameters
        ----------

        energy: array_like of :obj:`float`
            The energy table for the range :math:`0-\\pi`.
        force: array_like of :obj:`float`
            The force table for the range :math:`0-\\pi`.

        """

        _so_name = "Interactions::TabulatedAngleBond"

        pi = 3.14159265358979

        def __init__(self, *args, **kwargs):
            if len(args) == 0:
                kwargs.update({"min": 0., "max": self.pi})
            super().__init__(*args, **kwargs)

        def type_number(self):
            return BONDED_IA_TABULATED_ANGLE

        def type_name(self):
            """Name of interaction type.

            """
            return "TABULATED_ANGLE"

        def validate_params(self, params):
            """Check that parameters are valid.

            """
            phi = [params["min"], params["max"]]
            if abs(phi[0] - 0.) > 1e-5 or abs(phi[1] - self.pi) > 1e-5:
                raise ValueError(f"Tabulated angle expects forces/energies "
                                 f"within the range [0, pi], got {phi}")

    @script_interface_register
    class TabulatedDihedral(_TabulatedBase):

        """
        Tabulated bond dihedral.

        Parameters
        ----------

        energy: array_like of :obj:`float`
            The energy table for the range :math:`0-2\\pi`.
        force: array_like of :obj:`float`
            The force table for the range :math:`0-2\\pi`.

        """

        _so_name = "Interactions::TabulatedDihedralBond"

        pi = 3.14159265358979

        def __init__(self, *args, **kwargs):
            if len(args) == 0:
                kwargs.update({"min": 0., "max": 2. * self.pi})
            super().__init__(*args, **kwargs)

        def type_number(self):
            return BONDED_IA_TABULATED_DIHEDRAL

        def type_name(self):
            """Name of interaction type.

            """
            return "TABULATED_DIHEDRAL"

        def validate_params(self, params):
            """Check that parameters are valid.

            """
            phi = [params["min"], params["max"]]
            if abs(phi[0] - 0.) > 1e-5 or abs(phi[1] - 2 * self.pi) > 1e-5:
                raise ValueError(f"Tabulated dihedral expects forces/energies "
                                 f"within the range [0, 2*pi], got {phi}")


@script_interface_register
class Virtual(BondedInteraction):

    """
    Virtual bond.
    """

    _so_name = "Interactions::VirtualBond"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def type_number(self):
        return BONDED_IA_VIRTUAL_BOND

    def type_name(self):
        """Name of interaction type.

        """
        return "VIRTUAL"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class AngleHarmonic(BondedInteraction):

    """
    Bond-angle-dependent harmonic potential.

    Parameters
    ----------
    phi0 : :obj:`float`
        Equilibrium bond angle in radians.
    bend : :obj:`float`
        Magnitude of the bond interaction.

    """

    _so_name = "Interactions::AngleHarmonicBond"

    def type_number(self):
        return BONDED_IA_ANGLE_HARMONIC

    def type_name(self):
        """Name of interaction type.

        """
        return "ANGLE_HARMONIC"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class AngleCosine(BondedInteraction):

    """
    Bond-angle-dependent cosine potential.

    Parameters
    ----------
    phi0 : :obj:`float`
        Equilibrium bond angle in radians.
    bend : :obj:`float`
        Magnitude of the bond interaction.

    """

    _so_name = "Interactions::AngleCosineBond"

    def type_number(self):
        return BONDED_IA_ANGLE_COSINE

    def type_name(self):
        """Name of interaction type.

        """
        return "ANGLE_COSINE"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class AngleCossquare(BondedInteraction):

    """
    Bond-angle-dependent cosine squared potential.

    Parameters
    ----------
    phi0 : :obj:`float`
        Equilibrium bond angle in radians.
    bend : :obj:`float`
        Magnitude of the bond interaction.

    """

    _so_name = "Interactions::AngleCossquareBond"

    def type_number(self):
        return BONDED_IA_ANGLE_COSSQUARE

    def type_name(self):
        """Name of interaction type.

        """
        return "ANGLE_COSSQUARE"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class IBM_Triel(BondedInteraction):

    """
    IBM Triel bond.

    See Figure C.1 in :cite:`kruger12a`.

    Parameters
    ----------
    ind1, ind2, ind3 : :obj:`int`
        First, second and third bonding partner. Used for
        initializing reference state
    k1 : :obj:`float`
        Shear elasticity for Skalak and Neo-Hookean
    k2 : :obj:`float`, optional
        Area resistance for Skalak
    maxDist : :obj:`float`
        Gives an error if an edge becomes longer than maxDist
    elasticLaw : :obj:`str`, \{'NeoHookean', 'Skalak'\}
        Type of elastic bond

    """

    _so_name = "Interactions::IBMTriel"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def type_number(self):
        return BONDED_IA_IBM_TRIEL

    def type_name(self):
        return "IBM_Triel"

    def valid_keys(self):
        return {"ind1", "ind2", "ind3", "k1", "k2", "maxDist", "elasticLaw"}

    def validate_params(self, params):
        """Check that parameters are valid.

        """
        if params['elasticLaw'] not in {'NeoHookean', 'Skalak'}:
            raise ValueError(f"Unknown elasticLaw: '{params['elasticLaw']}'")

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {"k2": 0}

    def _get_params_from_es_core(self):
        return \
            {"maxDist": self.maxDist,
             "k1": self.k1,
             "k2": self.k2,
             "elasticLaw": self.elasticLaw}


@script_interface_register
class IBM_Tribend(BondedInteraction):

    """
    IBM Tribend bond.

    See Figure C.2 in :cite:`kruger12a`.

    Parameters
    ----------
    ind1, ind2, ind3, ind4 : :obj:`int`
        First, second, third and fourth bonding partner. Used for
        initializing reference state
    kb : :obj:`float`
        Bending modulus
    refShape : :obj:`str`, optional, \{'Flat', 'Initial'\}
        Reference shape, default is ``'Flat'``

    """

    _so_name = "Interactions::IBMTribend"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def type_number(self):
        return BONDED_IA_IBM_TRIBEND

    def type_name(self):
        return "IBM_Tribend"

    def valid_keys(self):
        return {"ind1", "ind2", "ind3", "ind4", "kb", "refShape"}

    def validate_params(self, params):
        """Check that parameters are valid.

        """
        if params['refShape'] not in {'Flat', 'Initial'}:
            raise ValueError(f"Unknown refShape: '{params['refShape']}'")

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {"refShape": "Flat"}

    def _get_params_from_es_core(self):
        return {"kb": self.kb, "theta0": self.theta0,
                "refShape": self.refShape}


@script_interface_register
class IBM_VolCons(BondedInteraction):

    """
    IBM volume conservation bond.

    See Figure C.3 in :cite:`kruger12a`.

    Parameters
    ----------
    softID : :obj:`int`
        Used to identify the object to which this bond belongs. Each object
        (cell) needs its own ID. For performance reasons, it is best to
        start from ``softID=0`` and increment by 1 for each subsequent bond.
    kappaV : :obj:`float`
        Modulus for volume force

    """

    _so_name = "Interactions::IBMVolCons"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def type_number(self):
        return BONDED_IA_IBM_VOLUME_CONSERVATION

    def type_name(self):
        return "IBM_VolCons"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}

    def current_volume(self):
        """
        Query the current volume of the soft object associated to this bond.
        The volume is initialized once all :class:`IBM_Triel` bonds have
        been added and the forces have been recalculated.
        """
        return immersed_boundaries.get_current_volume(self.softID)


@script_interface_register
class OifGlobalForces(BondedInteraction):

    """
    Characterize the distribution of the force of the global mesh deformation
    onto individual vertices of the mesh.

    Part of the :ref:`Object-in-fluid` method.

    Parameters
    ----------
    A0_g : :obj:`float`
        Relaxed area of the mesh
    ka_g : :obj:`float`
        Area coefficient
    V0 : :obj:`float`
        Relaxed volume of the mesh
    kv : :obj:`float`
        Volume coefficient

    """

    _so_name = "Interactions::OifGlobalForcesBond"

    def type_number(self):
        return BONDED_IA_OIF_GLOBAL_FORCES

    def type_name(self):
        """Name of interaction type.

        """
        return "OIF_GLOBAL_FORCES"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class OifLocalForces(BondedInteraction):

    """
    Characterize the deformation of two triangles sharing an edge.

    Part of the :ref:`Object-in-fluid` method.

    Parameters
    ----------
    r0 : :obj:`float`
        Equilibrium bond length of triangle edges
    ks : :obj:`float`
        Non-linear stretching coefficient of triangle edges
    kslin : :obj:`float`
        Linear stretching coefficient of triangle edges
    phi0 : :obj:`float`
        Equilibrium angle between the two triangles
    kb : :obj:`float`
        Bending coefficient for the angle between the two triangles
    A01 : :obj:`float`
        Equilibrium surface of the first triangle
    A02 : :obj:`float`
        Equilibrium surface of the second triangle
    kal : :obj:`float`
        Stretching coefficient of a triangle surface
    kvisc : :obj:`float`
        Viscous coefficient of the triangle vertices

    """

    _so_name = "Interactions::OifLocalForcesBond"

    def type_number(self):
        return BONDED_IA_OIF_LOCAL_FORCES

    def type_name(self):
        """Name of interaction type.

        """
        return "OIF_LOCAL_FORCES"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


@script_interface_register
class QuarticBond(BondedInteraction):

    """
    Quartic bond.

    Parameters
    ----------
    k0 : :obj:`float`
        Magnitude of the square term.
    k1 : :obj:`float`
        Magnitude of the fourth order term.
    r : :obj:`float`
        Equilibrium bond length.
    r_cut : :obj:`float`
        Maximum interaction length.
    """

    _so_name = "Interactions::QuarticBond"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def type_number(self):
        return BONDED_IA_QUARTIC

    def type_name(self):
        """Name of interaction type.

        """
        return "QUARTIC"

    def get_default_params(self):
        """Gets default values of optional parameters.

        """
        return {}


bonded_interaction_classes = {
    int(BONDED_IA_FENE): FeneBond,
    int(BONDED_IA_HARMONIC): HarmonicBond,
    int(BONDED_IA_RIGID_BOND): RigidBond,
    int(BONDED_IA_DIHEDRAL): Dihedral,
    int(BONDED_IA_VIRTUAL_BOND): Virtual,
    int(BONDED_IA_ANGLE_HARMONIC): AngleHarmonic,
    int(BONDED_IA_ANGLE_COSINE): AngleCosine,
    int(BONDED_IA_ANGLE_COSSQUARE): AngleCossquare,
    int(BONDED_IA_OIF_GLOBAL_FORCES): OifGlobalForces,
    int(BONDED_IA_OIF_LOCAL_FORCES): OifLocalForces,
    int(BONDED_IA_IBM_TRIEL): IBM_Triel,
    int(BONDED_IA_IBM_TRIBEND): IBM_Tribend,
    int(BONDED_IA_IBM_VOLUME_CONSERVATION): IBM_VolCons,
    int(BONDED_IA_THERMALIZED_DIST): ThermalizedBond,
    int(BONDED_IA_QUARTIC): QuarticBond,
}
IF ELECTROSTATICS:
    bonded_interaction_classes[int(BONDED_IA_BONDED_COULOMB)] = BondedCoulomb
    bonded_interaction_classes[
        int(BONDED_IA_BONDED_COULOMB_SR)] = BondedCoulombSRBond
IF TABULATED:
    bonded_interaction_classes[
        int(BONDED_IA_TABULATED_DISTANCE)] = TabulatedDistance
    bonded_interaction_classes[
        int(BONDED_IA_TABULATED_ANGLE)] = TabulatedAngle
    bonded_interaction_classes[
        int(BONDED_IA_TABULATED_DIHEDRAL)] = TabulatedDihedral


def get_bonded_interaction_type_from_es_core(bond_id):
    return < enum_bonded_interaction > bonded_ia_params_zero_based_type(bond_id)


@script_interface_register
class BondedInteractions(ScriptObjectMap):

    """
    Represents the bonded interactions list.

    Individual interactions can be accessed using ``BondedInteractions[i]``,
    where ``i`` is the bond id.

    Methods
    -------
    remove()
        Remove a bond from the list.
        This is a no-op if the bond does not exist.

        Parameters
        ----------
        bond_id : :obj:`int`

    clear()
        Remove all bonds.

    """

    _so_name = "Interactions::BondedInteractions"
    _so_creation_policy = "GLOBAL"

    def add(self, *args, **kwargs):
        """
        Add a bond to the list.

        Parameters
        ----------
        bond: :class:`espressomd.interactions.BondedInteraction`
            Either a bond object...
        \*\*kwargs : any
            ... or parameters to construct a
            :class:`~espressomd.interactions.BondedInteraction` object

        """

        if len(args) == 1 and isinstance(args[0], BondedInteraction):
            bonded_ia = args[0]
        else:
            raise TypeError("A BondedInteraction object needs to be passed.")
        bond_id = self._insert_bond(None, bonded_ia)
        return bond_id

    def __getitem__(self, bond_id):
        self._assert_key_type(bond_id)

        if self.call_method('has_bond', bond_id=bond_id):
            bond_obj = self.call_method('get_bond', bond_id=bond_id)
            bond_obj._bond_id = bond_id
            return bond_obj

        # Find out the type of the interaction from ESPResSo
        bond_type = get_bonded_interaction_type_from_es_core(bond_id)

        # Check if the bonded interaction exists in ESPResSo core
        if bond_type == BONDED_IA_NONE:
            raise ValueError(f"The bond with id {bond_id} is not yet defined.")

        # Find the appropriate class representing such a bond
        bond_class = bonded_interaction_classes[bond_type]

        # Create a new script interface object (i.e. a copy of the shared_ptr)
        # which links to the bonded interaction object
        return bond_class(bond_id)

    def __setitem__(self, bond_id, bond_obj):
        self._insert_bond(bond_id, bond_obj)

    def _insert_bond(self, bond_id, bond_obj):
        """
        Inserts a new bond. If a ``bond_id`` is given, the bond is inserted at
        that id. If no id is given, a new id is generated.

        Bonds can only be overwritten if the new bond is of the same type as the
        old one, e.g. a :class:`~espressomd.interactions.FeneBond` bond can only
        be overwritten by another :class:`~espressomd.interactions.FeneBond` bond.
        """

        # Validate arguments
        if not isinstance(bond_obj, BondedInteraction):
            raise ValueError(
                "Only subclasses of BondedInteraction can be assigned.")

        # Send the script interface object pointer to the core
        if bond_id is None:
            bond_id = self.call_method("insert", object=bond_obj)
        else:
            # Throw error if attempting to overwrite a bond of different type
            self._assert_key_type(bond_id)
            if self.call_method("contains", key=bond_id):
                old_type = bonded_interaction_classes[
                    get_bonded_interaction_type_from_es_core(bond_id)]
                if not type(bond_obj) is old_type:
                    raise ValueError(
                        "Bonds can only be overwritten by bonds of equal type.")
            self.call_method("insert", key=bond_id, object=bond_obj)

        # Save the bond id in the BondedInteraction instance
        bond_obj._bond_id = bond_id

        return bond_id

    def __len__(self):
        return self.call_method('get_size')

    # Support iteration over active bonded interactions
    def __iter__(self):
        for bond_id in self.call_method('get_bond_ids'):
            if get_bonded_interaction_type_from_es_core(bond_id):
                yield self[bond_id]

    def __getstate__(self):
        params = {}
        for bond_id in self.call_method('get_bond_ids'):
            if get_bonded_interaction_type_from_es_core(bond_id):
                bond_obj = self[bond_id]
                if hasattr(bond_obj, 'params'):
                    params[bond_id] = (
                        bond_obj._ctor_params, bond_obj.type_number())
        return params

    def __setstate__(self, params):
        for bond_id, (bond_params, bond_type) in params.items():
            self[bond_id] = bonded_interaction_classes[bond_type](
                **bond_params)
