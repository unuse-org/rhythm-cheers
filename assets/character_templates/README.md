# キャラクター生成素材

`normal.png`から`failure.png`は、顔を合成する身体テンプレートです。5枚とも628×1116の透過RGBAへ揃えています。

`decorations/`には、顔を基準に個別配置するための透過素材を格納しています。

- `hair.png`：髪
- `mustache.png`：口髭
- `cheeks.png`：左右一組の頬
- `failure_mark.png`：失敗状態の怒り記号

`CharacterGenerationService`は4枚を個別にC++へ渡します。髪とひげは全状態、ほっぺは成功状態、失敗マークは失敗状態へ合成されます。素材内の透明余白は、位置と大きさを計算する前にC++側で除外します。ひげの幅・中心・角度はYuNetが検出した左右の口角から決めます。

`default_hair.png`、`success_overlay.png`、`failure_overlay.png`は旧方式の合成済み素材です。現在の画像生成処理からは参照されません。

`models/face_detection_yunet_2023mar.onnx`は[OpenCV ZooのYuNet顔検出モデル](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet)です。SHA-256は`8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`です。モデルのMITライセンスは`models/YUNET_LICENSE.txt`を参照してください。

OpenCVのライセンスは`native/kanpai_image/third_party_licenses/opencv.txt`を参照してください。
