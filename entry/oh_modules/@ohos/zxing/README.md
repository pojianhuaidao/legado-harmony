# zxing

## Introduction
zxing is a library for parsing and generating one-dimensional and two-dimensional barcodes.

> ![code128.png](images/code128-EN.png)
>
> ![qrCode.png](images/qrCode-EN.png)

## Supported Barcode Formats
> For QR_CODE, DATA_MATRIX, AZTEC, PDF_417, and MAXICODE, the width and height passed during generation and decoding do not support decimal numbers.

| 1D Product   | 1D Industrial | 2D          |
| :----------- | :------------ | :---------- |
| UPC-A        | Code 39       | QR Code     |
| UPC-E        | Code 93       | Data Matrix |
| EAN-8        | Code 128      | Aztec       |
| EAN-13       | Codabar       | PDF 417     |
| RSS-14       | ITF           | MaxiCode    |
| RSS-Expanded |               |             |

## How to Install

````
ohpm install @ohos/zxing 
````
For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).


## How to Use

### Decoding

```js
import {MultiFormatReader, BarcodeFormat, DecodeHintType, RGBLuminanceSource, BinaryBitmap, HybridBinarizer } from "@ohos/zxing";
const hints = new Map();
const formats = [BarcodeFormat.QR_CODE];
hints.set(DecodeHintType.POSSIBLE_FORMATS, formats);
const reader = new MultiFormatReader();
reader.setHints(hints);
const luminanceSource = new RGBLuminanceSource(luminances, width, height);
const binaryBitmap = new BinaryBitmap(new HybridBinarizer(luminanceSource));
let result = reader.decode(binaryBitmap);
let text = result.getText();
```

### Encoding

```js
import {BarcodeFormat, MultiFormatWriter, BitMatrix, ZXingStringEncoding, EncodeHintType} from '@ohos/zxing';
 const encodeHintTypeMap = new Map();
 // Set the margin for the QR code.
 encodeHintTypeMap.set(EncodeHintType.MARGIN, 0);
 const writer: MultiFormatWriter = new MultiFormatWriter();
 let matrix: BitMatrix = writer.encode(content, BarcodeFormat.QR_CODE, width, height, encodeHintTypeMap);
```


In OpenHarmony, images are displayed in **Image** components, which do not support the bit matrix. Therefore, you need to convert the matrix into a pixel map so that the image can be properly displayed.

1. Convert the matrix into the pixel map buffer.

2. Create a pixel map based on the buffer.

3. Note the following constraints on barcode parsing and generation:

   - A Codabar barcode can contain only digits.
   - An EAN-8 barcode must be a 7-digit number.
   - An EAN-13 barcode must be a 12-digit number.
   - An ITF barcode can contain only digits and must be an even number. The generated code can be parsed only when the value length is greater than or equal to 6.
   - An UPC-A barcode must be an 11-digit number.
   - An UPC-E barcode must be a 7-digit number.

For details, see the demo code. The main conversion logic is encapsulated in the **imageUtils** class.

## Available APIs

#### Encoding
| Class             | API                                                      | Description                                                        |
| ----------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| QRCodeWriter      | encode(contents: string,format:  BarcodeFormat,width: int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a QR code.                                              |
| DataMatrixWriter  | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a data matrix barcode.                                          |
| AztecWriter       | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates an Aztec barcode.                                               |
| PDF417Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a PDF417 barcode.                                              |
| Code39Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a Code 39 barcode.                                              |
| Code93Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a Code 93 barcode.                                              |
| Code128Writer     | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a Code 128 barcode.                                             |
| CodaBarWriter     | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a CodaBar barcode.                                             |
| ITFWriter         | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates an ITF barcode.                                                 |
| UPCAWriter        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a UPC-A barcode.                                                |
| UPCEWriter        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates a UPC-E barcode.                                                |
| EAN8Writer        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates an EAN-8 barcode.                                                |
| EAN13Writer       | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Generates an EAN-13 barcode.                                               |
| MultiFormatWriter | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | Finds an appropriate Writer subclass for the barcode format requested and encodes the barcode with the supplied content. It is a factory class method.|

#### Decoding
| Class             | API                                                      | Description                                                        |
| ----------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| QRCodeReader      | decode(image: BinaryBitmap, hints?:  Map<DecodeHintType, any> \| null): Result; | Parses a QR code.                                              |
| DataMatrixReader  | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a data matrix barcode.                                          |
| AztecReader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an Aztec barcode.                                               |
| PDF417Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a PDF417 barcode.                                              |
| MaxiCodeReader    | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a MaxiCode barcode.                                            |
| Code39Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a Code 39 barcode.                                              |
| Code93Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a Code 93 barcode.                                              |
| CodaBarReader     | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a CodaBar barcode.                                             |
| Code128Reader     | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a Code 128 barcode.                                             |
| ITFReader         | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an ITF barcode.                                                 |
| UPCAReader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a UPC-A barcode.                                                |
| UPCEReader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses a UPC-E barcode.                                                |
| EAN8Reader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an EAN-8 barcode.                                                |
| EAN13Reader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an EAN-13 barcode.                                               |
| RSS14Reader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an RSS 14 barcode.                                               |
| RSSExpandedReader | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Parses an RSSExpanded barcode.                                         |
| MultiFormatReader | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | Finds an appropriate Reader subclass for the barcode format requested and decodes the barcode with the supplied content. It is a factory class method.|

#### Camera Component
| Component  |      |      |
| ---------- | ---- | ---- |
| CameraView |      |      |

#### CameraService
| Class                 | API                                        | Description            |
| --------------------- | ---------------------------------------------- | ---------------- |
| init(context:Context) | CameraService.getInstance().init(getContext()) | Opens a camera and initializes it.|
| destroy               | CameraService.getInstance().destroy()          | Closes a camera.        |
| release               | CameraService.getInstance().release()          | Releases a camera.            |

#### GlobalContext
| Class     | API                                           | Description  |
| --------- | ------------------------------------------------- | ------ |
| setObject | GlobalContext.getContext().setObject("key",value) | Sets the value.|
| getObject | GlobalContext.getContext().getObject("key")       | Obtains the value.|

## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- If you want the zxing library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/zxing
```

## Constraints

This project has been verified in the following version:

- DevEco Studio: 5.0 (5.0.3.122), SDK: API 12 (5.0.0.17)
- DevEco Studio: 4.1 Canary (4.1.3.322), SDK: API 11 (4.1.0.36)
- DevEco Studio: 4.1 Canary (4.1.3.220), SDK: API 11 (4.1.2.1)
- DevEco Studio: 4.0 Beta2 (4.0.3.500), SDK: API 10 (4.0.10.7)
- DevEco Studio: 4.0 Canary2 (4.0.3.317), SDK: API 10 (4.0.9.5)
- DevEco Studio: 3.1 Beta2 (3.1.0.400), SDK: API 9 Release (3.2.11.9)

## Directory Structure
````
|---- Zxing  
|     |---- entry  # Sample code
|     |---- library  # zxing library
|           |---- index.ets  # External APIs
|     |---- README.md  # Readme     
|     |---- README_zh.md  # Readme               
````

## How to Contribute
If you find any problem during the use, submit an [Issue](https://gitcode.com/openharmony-tpc/zxing/issues) or a [PR](https://gitcode.com/openharmony-tpc/zxing/pulls).

## License
This project is licensed under [Apache License 2.0](https://gitcode.com/openharmony-tpc/zxing/blob/master/LICENSE).
