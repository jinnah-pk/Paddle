cc_test_old(
  test_mkldnn_op_nhwc
  SRCS
  mkldnn/test_mkldnn_op_nhwc.cc
  DEPS
  op_registry
  pool_op
  shape_op
  crop_op
  activation_op
  generated_op
  pooling
  transpose_op
  fused_transpose_op
  scope
  device_context
  enforce
  executor)
