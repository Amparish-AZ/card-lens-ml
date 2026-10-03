"""Builds the tiny numeric-feature classifier bundled with CardLens."""
import flatbuffers
import numpy as np
import tflite
from pathlib import Path

# Features: email, phone, web, address, title, company, letters, digits,
# words, uppercase ratio, position from top, length (all normalized in Dart).
weights = np.array([
  [-4,-4,-3,-2,-2,-2, 5,-3, 2, 1,-3, 0], # name
  [-3,-3,-2,-2, 8,-2, 2,-2, 1, 0, 0, 0], # title
  [-3,-3,-2,-1,-1, 8, 2,-1, 1, 1, 0, 0], # company
  [10,-5,-2,-3,-3,-3,-2, 0,-2,-2, 0, 0], # email
  [-5,10,-4,-2,-3,-3,-4, 4,-2,-2, 0, 0], # phone
  [-3,-4,10,-3,-3,-2,-2, 0,-2,-2, 0, 0], # website
  [-4,-3,-3, 9,-2,-1, 1, 2, 2,-1, 2, 1], # address
], dtype=np.float32)
bias = np.array([0,-1,-1,-2,-2,-2,-1], dtype=np.float32)

b=flatbuffers.Builder(4096)
desc=b.CreateString('CardLens field classifier v1')
names=[b.CreateString(x) for x in ('features','weights','bias','scores')]

def buffer(data=b''):
  vec=b.CreateByteVector(data) if data else 0
  tflite.BufferStart(b)
  if vec: tflite.BufferAddData(b,vec)
  return tflite.BufferEnd(b)
buffers=[buffer(),buffer(weights.tobytes()),buffer(bias.tobytes())]

def tensor(name,shape,buf):
  tflite.TensorStartShapeVector(b,len(shape))
  for v in reversed(shape): b.PrependInt32(v)
  shape_vec=b.EndVector()
  tflite.TensorStart(b);tflite.TensorAddShape(b,shape_vec);tflite.TensorAddType(b,tflite.TensorType.FLOAT32);tflite.TensorAddBuffer(b,buf);tflite.TensorAddName(b,name)
  return tflite.TensorEnd(b)
tensors=[tensor(names[0],[1,12],0),tensor(names[1],[7,12],1),tensor(names[2],[7],2),tensor(names[3],[1,7],0)]

tflite.FullyConnectedOptionsStart(b)
fc=tflite.FullyConnectedOptionsEnd(b)
tflite.OperatorStartInputsVector(b,3)
for v in reversed([0,1,2]): b.PrependInt32(v)
inputs=b.EndVector()
tflite.OperatorStartOutputsVector(b,1);b.PrependInt32(3);outputs=b.EndVector()
tflite.OperatorStart(b);tflite.OperatorAddOpcodeIndex(b,0);tflite.OperatorAddInputs(b,inputs);tflite.OperatorAddOutputs(b,outputs);tflite.OperatorAddBuiltinOptionsType(b,tflite.BuiltinOptions.FullyConnectedOptions);tflite.OperatorAddBuiltinOptions(b,fc);op=tflite.OperatorEnd(b)

tflite.SubGraphStartTensorsVector(b,len(tensors))
for x in reversed(tensors): b.PrependUOffsetTRelative(x)
tensor_vec=b.EndVector()
tflite.SubGraphStartInputsVector(b,1);b.PrependInt32(0);sg_inputs=b.EndVector()
tflite.SubGraphStartOutputsVector(b,1);b.PrependInt32(3);sg_outputs=b.EndVector()
tflite.SubGraphStartOperatorsVector(b,1);b.PrependUOffsetTRelative(op);ops=b.EndVector()
sg_name=b.CreateString('main')
tflite.SubGraphStart(b);tflite.SubGraphAddTensors(b,tensor_vec);tflite.SubGraphAddInputs(b,sg_inputs);tflite.SubGraphAddOutputs(b,sg_outputs);tflite.SubGraphAddOperators(b,ops);tflite.SubGraphAddName(b,sg_name);subgraph=tflite.SubGraphEnd(b)

tflite.OperatorCodeStart(b);tflite.OperatorCodeAddBuiltinCode(b,tflite.BuiltinOperator.FULLY_CONNECTED);tflite.OperatorCodeAddDeprecatedBuiltinCode(b,tflite.BuiltinOperator.FULLY_CONNECTED);tflite.OperatorCodeAddVersion(b,1);opcode=tflite.OperatorCodeEnd(b)
tflite.ModelStartOperatorCodesVector(b,1);b.PrependUOffsetTRelative(opcode);opcodes=b.EndVector()
tflite.ModelStartSubgraphsVector(b,1);b.PrependUOffsetTRelative(subgraph);subgraphs=b.EndVector()
tflite.ModelStartBuffersVector(b,len(buffers))
for x in reversed(buffers): b.PrependUOffsetTRelative(x)
buffer_vec=b.EndVector()
tflite.ModelStart(b);tflite.ModelAddVersion(b,3);tflite.ModelAddOperatorCodes(b,opcodes);tflite.ModelAddSubgraphs(b,subgraphs);tflite.ModelAddDescription(b,desc);tflite.ModelAddBuffers(b,buffer_vec);model=tflite.ModelEnd(b)
b.Finish(model,file_identifier=b'TFL3')
out=Path(__file__).parents[1]/'assets'/'models'/'card_field_classifier.tflite'
out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(b.Output());print(out, out.stat().st_size)
