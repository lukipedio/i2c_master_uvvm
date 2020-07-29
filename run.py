# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2014-2018, Lars Asplund lars.anders.asplund@gmail.com

from os.path import join, dirname
from vunit import VUnit

root = dirname(__file__)

vu = VUnit.from_argv()

vu.add_external_library("unisim", "C:/compile_simlib/modelsim/unisim")
vu.add_external_library("uvvm_util", "C:/work/progetti/verification/UVVM/uvvm_util/sim/uvvm_util")
vu.add_external_library("bitvis_vip_i2c", "C:/work/progetti/verification/UVVM/bitvis_vip_i2c/sim/bitvis_vip_i2c")

common_lib = vu.add_library("common_lib")

common_lib.add_source_files(join(root, "*.vhd"))
common_lib.add_source_files(join(root, "i2cslave", "*.v"))



vu.main()
