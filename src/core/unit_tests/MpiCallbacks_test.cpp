/*
  Copyright (C) 2016-2018 The ESPResSo project
    Max-Planck-Institute for Polymer Research, Theory Group

  This file is part of ESPResSo.

  ESPResSo is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  ESPResSo is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/** \file
 * Unit tests for the MpiCallbacks class.
 *
 */

#define BOOST_TEST_NO_MAIN
#define BOOST_TEST_MODULE MpiCallbacks test
#define BOOST_TEST_ALTERNATIVE_INIT_API
#define BOOST_TEST_DYN_LINK
#include <boost/test/unit_test.hpp>

#include "../MpiCallbacks.hpp"

#include <boost/mpi.hpp>

static bool called = false;

/**
 * Test that the implementation of callback_modell_t
 * correctly deserialize the parameters and call
 * the callback with them.
 */
BOOST_AUTO_TEST_CASE(callback_model_t) {
    using namespace Communication;
    boost::mpi::communicator world;

    boost::mpi::packed_oarchive::buffer_type buff;
    boost::mpi::packed_oarchive oa(world, buff);
    oa << 537 << 3.4;

    /* function pointer variant */
    {
        called = false;
        void (*fp)(int, double) = [](int i, double d){
            BOOST_CHECK_EQUAL(537, i);
            BOOST_CHECK_EQUAL(3.4, d);

            called = true;
        };

        auto cb = detail::make_model(fp);

        boost::mpi::packed_iarchive ia(world, buff);
        cb->operator()(ia);

        BOOST_CHECK(called);
    }

    /* Lambda */
    {
        called = false;
        auto cb = detail::make_model([state=19](int i, double d){
            BOOST_CHECK_EQUAL(19, state);
            BOOST_CHECK_EQUAL(537, i);
            BOOST_CHECK_EQUAL(3.4, d);

            called = true;
        });

        boost::mpi::packed_iarchive ia(world, buff);
        cb->operator()(ia);

        BOOST_CHECK(called);
    }
}

int main(int argc, char **argv) {
  boost::mpi::environment mpi_env(argc, argv);

  return boost::unit_test::unit_test_main(init_unit_test, argc, argv);
}
