# zxing

## 简介
> zxing是一个解析/生成一维码/二维码的库。
>
> ![code128.png](images/code128.png)
>
> ![qrCode.png](images/qrCode.png)

## 支持的码格式
> 其中QR_CODE、DATA_MATRIX、AZTEC、PDF_417、MAXICODE生成和解码时传入的宽高不支持小数

| 1D product   | 1D industrial | 2D          |
| :----------- | :------------ | :---------- |
| UPC-A        | Code 39       | QR Code     |
| UPC-E        | Code 93       | Data Matrix |
| EAN-8        | Code 128      | Aztec       |
| EAN-13       | Codabar       | PDF 417     |
| RSS-14       | ITF           | MaxiCode    |
| RSS-Expanded |               |             |

## 下载安装

````
ohpm install @ohos/zxing 
````
OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)


## 使用说明

### 解码

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

### 编码

```js
import {BarcodeFormat, MultiFormatWriter, BitMatrix, ZXingStringEncoding, EncodeHintType} from '@ohos/zxing';
 const encodeHintTypeMap = new Map();
 //设置二维码边空白的宽度
 encodeHintTypeMap.set(EncodeHintType.MARGIN, 0);
 const writer: MultiFormatWriter = new MultiFormatWriter();
 let matrix: BitMatrix = writer.encode(content, BarcodeFormat.QR_CODE, width, height, encodeHintTypeMap);
```


OpenHarmony上是用image组件显示图片的，所以需要将matrix转化成pixelMap这样才可以显示在image组件上面。

1.需要将matrix转成pixelMap的buffer。

2.在根据这个buffer去创建pixelMap。

3.输入的解析生成码的一些限制：

   codabar只能是数字 

   ena8 只能是7位数字 

   ena13只能是12位数字 

   ITF码只能是数字，且需要双数，长度要>=6才能解析生成码 

   upcA只能数字，且长度只能是11位。

   upcE只能数字，且长度只能是7位

具体操作细节可以看demo代码，主要转换逻辑都封装在imageUtils工具类中。

## 接口列表

#### 编码
| 类名               | 方法名                                                                                                            | 功能                                                        |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------  |
| QRCodeWriter      | encode(contents: string,format:  BarcodeFormat,width: int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成QRCode码。                                                 |
| DataMatrixWriter  | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成DataMatrix码。                                             |
| AztecWriter       | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成Aztec码。                                                  |
| PDF417Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成PDF417码。                                                 |
| Code39Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成Code39码。                                                 |
| Code93Writer      | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成Code93码。                                                 |
| Code128Writer     | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成Code128码。                                                |
| CodaBarWriter     | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成CodaBar码。                                                |
| ITFWriter         | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成ITF码。                                                    |
| UPCAWriter        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成UPCA码。                                                   |
| UPCEWriter        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成UPCE码。                                                   |
| EAN8Writer        | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成EAN8码。                                                   |
| EAN13Writer       | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 生成EAN13码。                                                  |
| MultiFormatWriter | encode(contents: string,format: BarcodeFormat,width:  int,height:int,hints: Map<EncodeHintType, any>): BitMatrix | 这是一个工厂类方法，它为请求的条形码/二维码格式找到适当的编写器子类，并使用提供的内容编码二维码/条形码。 |

#### 解码
| 类名               | 方法名                                                                           | 功能                                                 |
| ----------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| QRCodeReader      | decode(image: BinaryBitmap, hints?:  Map<DecodeHintType, any> \| null): Result; | 解析QRCode码。                                                 |
| DataMatrixReader  | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析DataMatrix码。                                             |
| AztecReader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析Aztec码。                                                  |
| PDF417Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析PDF417码。                                                 |
| MaxiCodeReader    | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析MaxiCode码。                                               |
| Code39Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析Code39码。                                                 |
| Code93Reader      | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析Code93码。                                                 |
| CodaBarReader     | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析CodaBar码。                                                |
| Code128Reader     | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析Code128码。                                                |
| ITFReader         | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析ITF码。                                                    |
| UPCAReader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析UPCA码。                                                   |
| UPCEReader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析UPCE码。                                                   |
| EAN8Reader        | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析EAN8码。                                                   |
| EAN13Reader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析EAN13码。                                                  |
| RSS14Reader       | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析RSS14码。                                                  |
| RSSExpandedReader | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 解析RSSExpanded码。                                            |
| MultiFormatReader | decode(image: BinaryBitmap, hints?: Map<DecodeHintType, any> \|  null): Result; | 这是一个工厂类方法，它为请求的条形码/二维码格式找到适当的解码器子类，并使用提供的内容解码二维码/条形码。 |

#### 相机组件
| 组件名名                  |                                             |       |
|-----------------------|------------------------------------------------|---------|
| CameraView |  |  |

#### CameraService
| 类名                    | 方法名                                            | 功能      |
|-----------------------|------------------------------------------------|---------|
| init(context:Context) | CameraService.getInstance().init(getContext()) | 打开相机并初始化 |
| destroy               | CameraService.getInstance().destroy()          | 关闭相机    |
| release               | CameraService.getInstance().release()          | 释放      |

#### GlobalContext
| 类名            | 方法名                                            | 功能      |
|---------------|------------------------------------------------|---------|
| setObject     | GlobalContext.getContext().setObject("key",value) | 设置值 |
| getObject     | GlobalContext.getContext().getObject("key")          | 获取值    |

## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望zxing库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/zxing
```

## 约束与限制

在下述版本验证通过：
DevEco Studio: 5.0 (5.0.3.122), SDK: API12 (5.0.0.17)

DevEco Studio: 4.1 Canary(4.1.3.322), SDK: API11 (4.1.0.36)

DevEco Studio: 4.1 Canary(4.1.3.220), SDK: API11 (4.1.2.1)

DevEco Studio: 4.0 Beta2(4.0.3.500), SDK: API10 (4.0.10.7)

DevEco Studio: 4.0 Canary2(4.0.3.317), SDK: API10 (4.0.9.5)

DevEco Studio: 3.1 Beta2(3.1.0.400), SDK: API9 Release(3.2.11.9)

## 项目目录
````
|---- Zxing  
|     |---- entry  # 示例代码文件夹
|     |---- library  # zxing库文件夹
|           |---- index.ets  # 对外接口
|     |---- README.md  # 安装使用方法    
|     |---- README_zh.md  # 安装使用方法                
````

## 贡献代码
使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/openharmony-tpc/zxing/issues) 给组件，当然，也非常欢迎发 [PR](https://gitcode.com/openharmony-tpc/zxing/pulls)共建。

## 开源协议
本项目基于 [Apache License 2.0](https://gitcode.com/openharmony-tpc/zxing/blob/master/LICENSE) ，请自由的享受和参与开源。
