/*
 * Copyright (C) 2010-2019 The ESPResSo project
 * Copyright (C) 2002,2003,2004,2005,2006,2007,2008,2009,2010
 *   Max-Planck-Institute for Polymer Research, Theory Group
 *
 * This file is part of ESPResSo.
 *
 * ESPResSo is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * ESPResSo is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#ifndef CORE_THERMOSTAT_HPP
#define CORE_THERMOSTAT_HPP
/** \file
 *  Implementation in \ref thermostat.cpp.
 */

#include "config.hpp"

#include "Particle.hpp"
#include "integrate.hpp"
#include "random.hpp"
#include "rotation.hpp"

#include <utils/Counter.hpp>
#include <utils/Vector.hpp>
#include <utils/math/rotation_matrix.hpp>

#include <cmath>
#include <tuple>

/** \name Thermostat switches */
/*@{*/
#define THERMO_OFF 0
#define THERMO_LANGEVIN 1
#define THERMO_DPD 2
#define THERMO_NPT_ISO 4
#define THERMO_LB 8
#define THERMO_BROWNIAN 16
/*@}*/

namespace Thermostat {

static auto noise = []() { return (d_random() - 0.5); };

#ifdef PARTICLE_ANISOTROPY
using GammaType = Utils::Vector3d;
#else
using GammaType = double;
#endif
} // namespace Thermostat

namespace {
/** @name Integrators parameters sentinels.
 *  These functions return the sentinel value for the Langevin/Brownian
 *  parameters, indicating that they have not been set yet.
 */
/*@{*/
constexpr double sentinel(double) { return -1.0; }
constexpr Utils::Vector3d sentinel(Utils::Vector3d) {
  return {-1.0, -1.0, -1.0};
}
constexpr double set_nan(double) { return NAN; }
constexpr Utils::Vector3d set_nan(Utils::Vector3d) { return {NAN, NAN, NAN}; }
/*@}*/
} // namespace

/************************************************
 * exported variables
 ************************************************/

/** Switch determining which thermostat(s) to use. This is a or'd value
 *  of the different possible thermostats (defines: \ref THERMO_OFF,
 *  \ref THERMO_LANGEVIN, \ref THERMO_DPD \ref THERMO_NPT_ISO). If it
 *  is zero all thermostats are switched off and the temperature is
 *  set to zero.
 */
extern int thermo_switch;

/** Temperature of the thermostat. */
extern double temperature;

/** True if the thermostat should act on virtual particles. */
extern bool thermo_virtual;

/** %Thermostat for Langevin dynamics. */
struct LangevinThermostat {
private:
  using GammaType = Thermostat::GammaType;

public:
  /** Translational friction coefficient @f$ \gamma_{\text{trans}} @f$. */
  GammaType gamma = sentinel(GammaType{});
  /** Rotational friction coefficient @f$ \gamma_{\text{rot}} @f$. */
  GammaType gamma_rotation = sentinel(GammaType{});
  /** Prefactor for the friction. */
  GammaType pref_friction;
  /** Prefactor for the translational velocity noise. */
  GammaType pref_noise;
  /** Prefactor for the angular velocity noise. */
  GammaType pref_noise_rotation;
  /** RNG counter, used for both translation and rotation. */
  std::unique_ptr<Utils::Counter<uint64_t>> rng_counter;
};

extern LangevinThermostat langevin;

/** Friction coefficient for nptiso-thermostat's function
 *  @ref friction_therm0_nptiso
 */
extern double nptiso_gamma0;
/** Friction coefficient for nptiso-thermostat's function
 *  @ref friction_thermV_nptiso
 */
extern double nptiso_gammav;

/** %Thermostat for Brownian dynamics. */
struct BrownianThermostat {
private:
  using GammaType = Thermostat::GammaType;

public:
  /** Translational friction coefficient @f$ \gamma_{\text{trans}} @f$. */
  GammaType gamma = sentinel(GammaType{});
  /** Rotational friction coefficient @f$ \gamma_{\text{rot}} @f$. */
  GammaType gamma_rotation = sentinel(GammaType{});
  /** Inverse of the translational noise standard deviation.
   *  Stores @f$ \left(\sqrt{2D_{\text{trans}}}\right)^{-1} @f$ with
   *  @f$ D_{\text{trans}} = k_B T/\gamma_{\text{trans}} @f$
   *  the translational diffusion coefficient
   */
  GammaType sigma_pos_inv = sentinel(GammaType{});
  /** Inverse of the rotational noise standard deviation.
   *  Stores @f$ \left(\sqrt{2D_{\text{rot}}}\right)^{-1} @f$ with
   *  @f$ D_{\text{rot}} = k_B T/\gamma_{\text{rot}} @f$
   *  the rotational diffusion coefficient
   */
  GammaType sigma_pos_rotation_inv = sentinel(GammaType{});
  /** Sentinel value for divisions by zero. */
  GammaType const gammatype_nan = set_nan(GammaType{});
  /** Translational velocity noise standard deviation. */
  double sigma_vel = 0;
  /** Angular velocity noise standard deviation. */
  double sigma_vel_rotation = 0;
  /** RNG counter, used for both translation and rotation. */
  std::unique_ptr<Utils::Counter<uint64_t>> rng_counter;
};

extern BrownianThermostat brownian;

/************************************************
 * functions
 ************************************************/

/** Only require seed if rng is not initialized. */
bool langevin_is_seed_required();

/** Only require seed if rng is not initialized. */
bool brownian_is_seed_required();

/** @name philox functionality: increment, get/set */
/*@{*/
void langevin_rng_counter_increment();
void langevin_set_rng_state(uint64_t counter);
uint64_t langevin_get_rng_state();
void brownian_rng_counter_increment();
void brownian_set_rng_state(uint64_t counter);
uint64_t brownian_get_rng_state();
/*@}*/

/** Initialize constants of the thermostat at the start of integration */
void thermo_init();

#ifdef NPT
/** Add velocity-dependent noise and friction for NpT-sims to the particle's
 *  velocity
 *  @param vj     j-component of the velocity
 *  @return       j-component of the noise added to the velocity, also scaled by
 *                dt (contained in prefactors)
 */
inline double friction_therm0_nptiso(double vj) {
  extern double nptiso_pref1, nptiso_pref2;
  if (thermo_switch & THERMO_NPT_ISO) {
    if (nptiso_pref2 > 0.0) {
      return (nptiso_pref1 * vj + nptiso_pref2 * Thermostat::noise());
    }
    return nptiso_pref1 * vj;
  }
  return 0.0;
}

/** Add p_diff-dependent noise and friction for NpT-sims to \ref
 *  nptiso_struct::p_diff
 */
inline double friction_thermV_nptiso(double p_diff) {
  extern double nptiso_pref3, nptiso_pref4;
  if (thermo_switch & THERMO_NPT_ISO) {
    if (nptiso_pref4 > 0.0) {
      return (nptiso_pref3 * p_diff + nptiso_pref4 * Thermostat::noise());
    }
    return nptiso_pref3 * p_diff;
  }
  return 0.0;
}
#endif

/** Langevin thermostat for particle translational velocities.
 *  Collects the particle velocity (different for ENGINE, PARTICLE_ANISOTROPY).
 *  Collects the langevin parameters kT, gamma (different for
 *  LANGEVIN_PER_PARTICLE). Applies the noise and friction term.
 */
inline Utils::Vector3d friction_thermo_langevin(Particle const &p) {
  // Early exit for virtual particles without thermostat
  if (p.p.is_virtual && !thermo_virtual) {
    return {};
  }

  // Determine prefactors for the friction and the noise term
  // first, set defaults
  Thermostat::GammaType langevin_pref_friction = langevin.pref_friction;
  Thermostat::GammaType langevin_pref_noise = langevin.pref_noise;
  // Override defaults if per-particle values for T and gamma are given
#ifdef LANGEVIN_PER_PARTICLE
  if (p.p.gamma >= Thermostat::GammaType{} or p.p.T >= 0.) {
    auto const constexpr langevin_temp_coeff = 24.0;
    auto const kT = p.p.T >= 0. ? p.p.T : temperature;
    auto const gamma =
        p.p.gamma >= Thermostat::GammaType{} ? p.p.gamma : langevin.gamma;
    langevin_pref_friction = -gamma;
    langevin_pref_noise = sqrt(langevin_temp_coeff * kT * gamma / time_step);
  }
#endif /* LANGEVIN_PER_PARTICLE */

  // Get effective velocity in the thermostatting
#ifdef ENGINE
  auto const &velocity = (p.p.swim.v_swim != 0)
                             ? p.m.v - p.p.swim.v_swim * p.r.calc_director()
                             : p.m.v;
#else
  auto const &velocity = p.m.v;
#endif
#ifdef PARTICLE_ANISOTROPY
  // Particle frictional isotropy check
  auto const aniso_flag =
      (langevin_pref_friction[0] != langevin_pref_friction[1]) ||
      (langevin_pref_friction[1] != langevin_pref_friction[2]);

  // In case of anisotropic particle: body-fixed reference frame. Otherwise:
  // lab-fixed reference frame.
  auto const friction_op =
      aniso_flag ? convert_body_to_space(p, diag_matrix(langevin_pref_friction))
                 : diag_matrix(langevin_pref_friction);
  auto const noise_op = diag_matrix(langevin_pref_noise);
#else
  auto const &friction_op = langevin_pref_friction;
  auto const &noise_op = langevin_pref_noise;
#endif // PARTICLE_ANISOTROPY
  using Random::v_noise;

  // Do the actual (isotropic) thermostatting
  return friction_op * velocity +
         noise_op * v_noise<RNGSalt::LANGEVIN>(langevin.rng_counter->value(),
                                               p.p.identity);
}

#ifdef ROTATION
/** Langevin thermostat for particle angular velocities.
 *  Collects the particle velocity (different for PARTICLE_ANISOTROPY).
 *  Collects the langevin parameters kT, gamma_rot (different for
 *  LANGEVIN_PER_PARTICLE). Applies the noise and friction term.
 */
inline Utils::Vector3d friction_thermo_langevin_rotation(const Particle &p) {

  auto langevin_pref_friction = -langevin.gamma_rotation;
  auto langevin_pref_noise = langevin.pref_noise_rotation;

  // Override defaults if per-particle values for T and gamma are given
#ifdef LANGEVIN_PER_PARTICLE
  if (p.p.gamma_rot >= Thermostat::GammaType{} or p.p.T >= 0.) {
    auto const constexpr langevin_temp_coeff = 24.0;
    auto const kT = p.p.T >= 0. ? p.p.T : temperature;
    auto const gamma = p.p.gamma_rot >= Thermostat::GammaType{}
                           ? p.p.gamma_rot
                           : langevin.gamma_rotation;
    langevin_pref_friction = -gamma;
    langevin_pref_noise = sqrt(langevin_temp_coeff * kT * gamma / time_step);
  }
#endif /* LANGEVIN_PER_PARTICLE */

  using Random::v_noise;

  // Here the thermostats happens
  auto const noise = v_noise<RNGSalt::LANGEVIN_ROT>(
      langevin.rng_counter->value(), p.p.identity);
#ifdef PARTICLE_ANISOTROPY
  return hadamard_product(langevin_pref_friction, p.m.omega) +
         hadamard_product(langevin_pref_noise, noise);
#else
  return langevin_pref_friction * p.m.omega + langevin_pref_noise * noise;
#endif
}

#endif // ROTATION
#endif
