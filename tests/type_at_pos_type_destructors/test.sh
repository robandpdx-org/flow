#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

queries_in_file "type-at-pos" "conditional-types.js"
queries_in_file "type-at-pos" "exact.js"
queries_in_file "type-at-pos" "react-component.js"
queries_in_file "type-at-pos" "spread.js"
queries_in_file "type-at-pos" "type-destructor.js"
queries_in_file "type-at-pos" "mapped-type.js"
queries_in_file "type-at-pos" "evaluated-size-limit.js"
