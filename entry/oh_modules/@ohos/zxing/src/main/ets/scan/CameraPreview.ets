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
import { CameraCodeScanConst } from './constants/CameraCodeScanConst';
import { CameraConstants, CameraPosition, CaptureMode } from './constants/CameraConstants';
import CameraLifecycle from './model/CameraLifecycle';
import CameraService from './model/CameraService';
import camera from '@ohos.multimedia.camera';
import { GlobalContext } from './utils/GlobalContext';
import display from '@ohos.display';


@ComponentV2
export default struct CameraPreview {
  private globalDisplay = GlobalContext.getContext().getObject("display") as display.Display
  private controller = new XComponentController();
  @Local viewHeight: number = this.globalDisplay.height;
  @Consumer(CameraConstants.CAPTURE_MODE_KEY) curCaptureMode: CaptureMode = CaptureMode.PREVIEW_FRAME;
  @Local animationOrdinate: number = CameraCodeScanConst.SCAN_TO_TOP_HEIGHT
  @Local timeId: number = -1
  aboutToAppear() {
    let that = this;
    let listenerData: CameraLifecycle = {
      onCameraConfigure(mode: CaptureMode, position: CameraPosition, resolution: camera.Size, resolutions: camera.Profile[]) {
        that.viewHeight = px2vp(resolution.width * that.globalDisplay.width / resolution.height);
        that.controller.setXComponentSurfaceSize({
          surfaceWidth: resolution.width,
          surfaceHeight: resolution.height
        });
      }
    }
    CameraService.getInstance().addLifecycleListener(listenerData);
    this.setQRCodeScanAnimation()
  }
  aboutToDisappear() {
    clearInterval(this.timeId)
    CameraService.getInstance().destroy()
  }
  // 扫描框中的线
  setQRCodeScanAnimation() {
    this.timeId = setInterval(() => {
      animateTo({
        duration: 1000, // 动画时间
        tempo: 0.5, // 动画速率
        curve: Curve.EaseInOut,
        delay: 200, // 动画延迟时间
        iterations: -1, // 动画是否重复播放
        playMode: PlayMode.Normal,
      }, () => {
        this.animationOrdinate = 390 // 扫描动画结束Y坐标
      })
    }, 2000)
  }

  @Builder
  ScanBorder() {
    Column() {
      Column() {
        Image($r('app.media.scan_border'))
          .width('100%')
          .height('100%')
          .margin({ top: CameraCodeScanConst.SCAN_TO_TOP_HEIGHT })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.animationOrdinate = (newValue.position.y as number) + 10
          })

        Divider()
          .strokeWidth(1)
          .height(4)
          .width('100%')
          .color(Color.White)
          .width('100%')
          .position({ x: 0, y: 0 })
          .translate({ x: 0, y: this.animationOrdinate })
      }
      .width(280)
      .height(280)

      Text($r('app.string.putTheQRCodeToScan'))
        .fontSize(18)
        .fontColor(Color.White)
        .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .margin({ right: 20, top: 20, left: 20 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  build() {
    Stack() {
      XComponent({
        id: CameraConstants.CAMERA_PREVIEW_ID,
        type: CameraConstants.CAMERA_PREVIEW_TYPE,
        controller: this.controller
      })
        .onLoad(() => {
          let renderId = this.controller.getXComponentSurfaceId();
          // 打开相机
          CameraService.getInstance().init(getContext(), renderId, this.curCaptureMode, CameraPosition.BACK);
        })
      // 扫描框
      this.ScanBorder()
    }
    .width('100%')
    .height(this.viewHeight)
  }
}