/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { CameraConstants, CameraPosition, CaptureMode } from './constants/CameraConstants';
import CameraService from './model/CameraService';
import router from '@ohos.router';
import CameraPreview from './CameraPreview';
import CameraLifecycle from './model/CameraLifecycle';
import camera from '@ohos.multimedia.camera';
import MainModel from './viewmodel/CustomCameraModel';
import DimensionUtil from './utils/DimensionUtil';
import prompt from '@ohos.promptAction'
import { CameraCodeScanConst, DecodeResultAttribute } from './constants/CameraCodeScanConst';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { MyStorage } from "./utils/CameraType"

@ComponentV2
export default struct CameraView {
  private mainModel: MainModel | null = null;
  @Local isQRCodeScanStopped: boolean = false
  @Provider(CameraConstants.CAPTURE_MODE_KEY) curCaptureMode: CaptureMode = CaptureMode.PREVIEW_FRAME;
  @Provider(CameraConstants.RATION_CHANGE_KEY) isRatioChanging: boolean = false;
  @Provider(CameraConstants.RATION_KEY) curRatio: number = CameraConstants.RATIO_DEFAULT_VALUE;
  @Provider(CameraConstants.RATION_ENABLE) isRatioEnable: boolean = false;

  aboutToAppear() {
    // DimensionUtil初始化，得到GlobalContext设置的值
    DimensionUtil.getInstance().init()
    let that = this;
    that.mainModel = MainModel.getInstant();
    let listenerData: CameraLifecycle = {
      onCameraConfigure(mode: CaptureMode, position: CameraPosition, resolution: camera.Size, resolutions: camera.Profile[]) {
        that.isRatioEnable = (position === CameraPosition.BACK);
        that.curCaptureMode = mode;
        (that.mainModel as MainModel).hideRationMenu(0, () => {
          that.isRatioChanging = false;
        });
      },
      onRatioChanged(outputRation: number, outputRationRage: number[]) {
        that.curRatio = outputRation;
      },
    }
    CameraService.getInstance().addLifecycleListener(listenerData);
  }

  aboutToDisappear() {
    CameraService.getInstance().destroy()
  }

  @Builder
  TopButton() {
    Row() {
      // 返回按钮
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Image($r('app.media.scan_back'))
          .width(DimensionUtil.getVp($r('app.float.camera_close_size')) / 2)
          .height(DimensionUtil.getVp($r('app.float.camera_close_size')) / 2).objectFit(ImageFit.Fill)
      }
      .backgroundColor('#00000000')
      .width(DimensionUtil.getVp($r('app.float.camera_close_size')))
      .height(DimensionUtil.getVp($r('app.float.camera_close_size')))
      .onClick(() => {
        router.back()
      })

      // 相册图片
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Image($r('app.media.scan_photo'))
          .width(DimensionUtil.getVp($r('app.float.camera_close_size')) / 2)
          .height(DimensionUtil.getVp($r('app.float.camera_close_size')) / 2).objectFit(ImageFit.Fill)
      }
      .backgroundColor('#00000000')
      .width(DimensionUtil.getVp($r('app.float.camera_close_size')))
      .height(DimensionUtil.getVp($r('app.float.camera_close_size')))
      .onClick(async () => {
        this.isQRCodeScanStopped = true;
        let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
        photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        photoSelectOptions.maxSelectNumber = 1;
        let uris: Array<string> = [];
        let photoViewPicker = new photoAccessHelper.PhotoViewPicker();
        let photoSelectResult: photoAccessHelper.PhotoSelectResult = await photoViewPicker.select(photoSelectOptions);
        uris = photoSelectResult.photoUris;
        await CameraService.getInstance().parseImageQRCode(uris[0], (showResult: DecodeResultAttribute) => {
          if (showResult != undefined && showResult.isSucess) {
            let decodeText = showResult.decodeResult;
            MyStorage.instance().qrCodeParseResult = decodeText
          } else {
            prompt.showToast({
              message: $r('app.string.scanCodeNotRecognized')
            });
          }
        });
      })
    }
    .width("100%")
    .margin({ top: 24 })
    .padding({ left: 24, right: 24 })
    .alignItems(VerticalAlign.Top)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      CameraPreview()
      this.TopButton()
    }
    .backgroundColor(Color.Black)
    .height("100%")
  }
}