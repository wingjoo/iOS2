//
//  LocationManager.swift
//  Tracks
//
//  스텝 수, 달린 거리를 측정. GPS, 가속도 센서 등을 컨트롤하는 클래스
//

import CoreMotion
import UIKit
import CoreLocation


//let ACCELEROMETER_TEMP_SIZE_MAX = 50
let MITER_PER_STEP: Double  = 1
//let ACCELEROMETER_CHECK_TIME_MILLIS = 300

/*
 GPS가 꺼져있을때는 스템수로서 거리를 측정
 MITER_PER_STEP/1000 으로 스텝수 1당 1m로 가정
 */


class LocationManager: NSObject, CLLocationManagerDelegate {
    
    /// gps를 이용한 트래킹을 켰는지 껐는지 (껐을 경우는 가속 센서를 이용해 트래킹)
    private var _gpsTrackingIsOn = true
    var gpsTrackingIsOn: Bool {
        return _gpsTrackingIsOn
    }
    
    func setGpsTrackingOn(gpsTrackingOn: Bool) {
        if _gpsTrackingIsOn==false && gpsTrackingOn == true {
            // gps가 꺼져 있었는데 킨 경우
            changeTrackingMethod(gpsTrackingOn)
        } else if _gpsTrackingIsOn==true && gpsTrackingOn == false {
            // gps가 켜져 있었는데 끈 경우
            changeTrackingMethod(gpsTrackingOn)
        }
        _gpsTrackingIsOn = gpsTrackingOn
    }
    

    
    /// 실제 gps 트래킹이 가능한 상태인지 여부 (현재는 권한이 부여됐는지만 검사)
    var gpsTrackingIsAvailable: Bool {
        if locationAuthorized {
            return true
        }
        return false
    }
    
    /// 사용자가 gps 권한을 허가 했는지 여부
    private var locationAuthorized = false
    /// gps 권한이 변경됐을 때 호출될 핸들러
    var didChangeAuthorization: ((isAuthorized: Bool)->Void)?
    
    // 안씀
    //private var locationFailedCount = 0
    
    private var locationManager: CLLocationManager = CLLocationManager()
 
    /// 트래킹을 중지했다가 위치가 이동된 상태에서 다시 시작했을 경우 시작 위치를 바꿔주고 이전까지의 거리를 합을 더해줘야 함
    private var startLocation: CLLocation?
    /// 처음 시작점이 튀는 경우가 있음. 데이터가 5~15번 정도 업데이트된 후부터 잡기
    private var dummyStartLocations: [CLLocation] = []
    
    /// gps트래킹 시작 지점이 설정된 위치부터 현재 위치까지의 거리
    private var distanceBetweenLocation: Double = 0
    /// 정지했다가 다시 뛸 경우나 gps 트래킹을 껐다가 켰을 경우에는 측정 시작지점이 바뀌므로 이전까지 측정값은 저장해놓고 합산해야 함
    private var distanceBetweenLocationArrayForSave: [Double] = []
    
    // 안씀
    //private var stepForCheck: Int64 = 0
    
    
    /// 가속도 센서를 이용한 스텝 측정에 사용
//    private var stepCheckUpdateMillis: Int64 = 0
//    private var accelerometerTempArray = [CMAcceleration]()
//    private lazy var motionManager = CMMotionManager()
    
    
    
    func formattedDistance(unit: DistanceUnit = Common.getDistanceUnit()) -> String {
        let distance = DISTANCE_WITH_UNIT(distanceKm)
        
        if distance <= 0 {
            return "0.00"
        } else if distance < 100 {
            var kmString = String(format: "%.3f", distance)
            // %.2가 반올림되서 표현 됨. rounding 되는 것 막기
            let index: String.Index = kmString.startIndex.advancedBy(kmString.characters.count-1)
            kmString = kmString.substringToIndex(index)
            return kmString
        } else {
            var kmString = String(format: "%.2f", distance)
            let index: String.Index = kmString.startIndex.advancedBy(kmString.characters.count-1)
            kmString = kmString.substringToIndex(index)
            return kmString
        }
    }
    var distanceKm: Double {
        
        // 가속도 센서로 트래킹동안의 이동거리를 스텝수로부터 유추해냄
        let kmWhileGpsOff = Double(stepCountWhileNotUsingGps)*MITER_PER_STEP/1000
        // gps 트래킹동안 측정한 이동거리
        let kmWhileGpsOn = totalDistanceByGps/1000
        
        let totalKm = kmWhileGpsOff + kmWhileGpsOn
        return totalKm
    }
    
    /// gps로 측정된 총 이동 거리의 합 (단위: m)
    private var totalDistanceByGps: Double {
        // 추적 시작 지점이 바뀌기 이전에 합산된 거리의 합
        var totalDistance = distanceBetweenLocationArrayForSave.reduce(0, combine: { $0 + $1 })
        // (아직 배열에 들어가 있지 않음)시작 지점이 바뀐 이후부터 현재까지 합산된 거리를 더해줌
        totalDistance += distanceBetweenLocation
        return totalDistance
    }
    
    /// 가속도 센서로 측정된 총 스텝 수
    private var _stepCount: Int64 = 0
    var stepCount: Int64 {
        get {
            /* gps일 때는 거리로 스텝을 계산하던 것이 변경됨
            if locationAuthorized && useGps {
                let convertedStep = Int64(totalDistanceByGps/MITER_PER_STEP)
                if self.stepForCheck <= convertedStep {
                    self.stepForCheck = convertedStep
                } else {
                    return self.stepForCheck
                }
                return convertedStep
            } */
            return _stepCount
        }
        set {
            _stepCount = newValue
        }
    }
    /// 측정된 스텝 수 중 gps tracking을 끈 상태에서 측정된 스텝의 수
    private var stepCountWhileNotUsingGps: Int64 = 0
    
    
    init(didChangeAuthorization: ((isAuthorized: Bool)->Void)?) {
        super.init()
        setUp(didChangeAuthorization)
    }

//    let kUpdateInterval  = 0.2
    
    func setUp(didChangeAuthorization: ((isAuthorized: Bool)->Void)?) {
        //locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.activityType = .Fitness
        
        locationManager.requestAlwaysAuthorization()
//        locationManager.requestWhenInUseAuthorization()
        
        self.didChangeAuthorization = didChangeAuthorization
        
        //
//        motionManager.accelerometerUpdateInterval = kUpdateInterval
        
        //
        
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            // Fallback on earlier versions
        }
    }
    
    
    /// 트래킹 방식이 변경됐을 경우 거리를 합산할 때 gps 측정 값을 갱신해줘야 함
    func changeTrackingMethod(gpsTrackingOn: Bool) {
        if gpsTrackingOn {
            locationManager.startUpdatingLocation()
        } else {
            stopUpdatingGpsLocation()
        }
    }
    
    
    //외부에서 호출하는 중지 메소드
    func stop() {
        //스텝수 구하기 스톱
        SOStepDetector.sharedInstance().stopDetection()
        stopUpdatingGpsLocation()
    }
    
    /// 업데이트 중지 + 다시 gps트래킹이 재개됐을 때, gps에 의한 이동거리를 재기 시작할 위치 초기화 + 기존 측정된 값은 저장 후 초기화 해주기
    private func stopUpdatingGpsLocation() {
        locationManager.stopUpdatingLocation()
        
        startLocation = nil
        dummyStartLocations = []
        
        if distanceBetweenLocation > 0 {
            distanceBetweenLocationArrayForSave.append(distanceBetweenLocation)
            distanceBetweenLocation = 0
        }
    }
    
    //데이터 초기화
    func initializeData() {
        
        self.startLocation = nil
        //self.locationFailedCount = 0
        self.distanceBetweenLocation = 0
        self.distanceBetweenLocationArrayForSave = []
        self.stepCount = 0
        self.stepCountWhileNotUsingGps = 0
        //self.stepForCheck = 0
        self.dummyStartLocations = []
//        self.stepCheckUpdateMillis = 0
    }
    
    func startUpdate() {
        locationManager.startUpdatingLocation()
        
        //step수 구하기
        self.startStep()
        
        /*
          Step 하는 알고리즘 변경 SOStepDetector 사용
        if motionManager.accelerometerAvailable {
            /*
             motionManager.startAccelerometerUpdatesToQueue(NSOperationQueue.mainQueue(), withHandler: {
             (accelerometerData, error) -> Void in
             accelerometerData?.acceleration
             })*/
            motionManager.startDeviceMotionUpdatesToQueue(NSOperationQueue.currentQueue()!, withHandler: {
                [weak self] (deviceMotion, error) in
                
                if let weakSelf = self {
                    if(weakSelf.stepCheckUpdateMillis == 0){
                        weakSelf.stepCheckUpdateMillis = weakSelf.currentTimeMillis()
                    }
                    
                    if (weakSelf.accelerometerTempArray.count >= ACCELEROMETER_TEMP_SIZE_MAX) {
                        weakSelf.accelerometerTempArray.removeFirst()
                    }
                    
                    if let acceleration = deviceMotion?.userAcceleration {
                        weakSelf.accelerometerTempArray.append(acceleration)
                    }
                    
                    if(weakSelf.currentTimeMillis() - weakSelf.stepCheckUpdateMillis >= ACCELEROMETER_CHECK_TIME_MILLIS) {
                        weakSelf.checkStep(weakSelf.accelerometerTempArray)
                        weakSelf.accelerometerTempArray.removeAll()
                        weakSelf.stepCheckUpdateMillis = weakSelf.currentTimeMillis()
                    }
                }
                
                })
        }
         */
    }
    
    
    /*
    private func currentTimeMillis() -> Int64{
        let nowDouble = NSDate().timeIntervalSince1970
        return Int64(nowDouble*1000)
    }
    
    
    let CHECK_VAL_ACCEL_X: Double = 0.5;
    let CHECK_VAL_ACCEL_Y: Double = 0.5;
    let CHECK_VAL_ACCEL_Z: Double = 0.5;
    
    private func checkStep(accelerations: [CMAcceleration]?) {
        if let accelerations = accelerations {
            let maxConstant = Double(CGFloat.max)
            var minValues = (x:maxConstant, y:maxConstant, z:maxConstant)
            var maxValues = (x:-maxConstant, y:-maxConstant, z:-maxConstant)
            for acceleration in accelerations {
                minValues.x = min(minValues.x, acceleration.x);
                minValues.y = min(minValues.y, acceleration.y);
                minValues.z = min(minValues.z, acceleration.z);
                
                maxValues.x = max(maxValues.x, acceleration.x);
                maxValues.y = max(maxValues.y, acceleration.y);
                maxValues.z = max(maxValues.z, acceleration.z);
            }
            
            let diffX = abs(maxValues.x - minValues.x);
            let diffY = abs(maxValues.y - minValues.y);
            let diffZ = abs(maxValues.z - minValues.z);
            
            if (diffX > CHECK_VAL_ACCEL_X && diffY > CHECK_VAL_ACCEL_Y && diffZ > CHECK_VAL_ACCEL_Z) {
                stepCount += 1;
                if gpsTrackingIsOn == false || startLocation==nil // 시작지점 잡는 동안은 거리측정을 스텝으로 하기
                {
                    stepCountWhileNotUsingGps += 1
                }
            }
        }
    }
     */
    //스텝 숫자 체크
    private func startStep() {
        //Starting pedometer
        SOStepDetector.sharedInstance().startDetectionWithUpdateBlock { (error) in
            if error != nil
            {
                print("%@", error.localizedDescription);
                return
            }
            
            self.stepCount += 1;
            
            //GPS가 꺼져 있는 상태일때의 스텝수(일반 스텝수랑 다른가?)
            if self.gpsTrackingIsOn == false || self.startLocation==nil // 시작지점 잡는 동안은 거리측정을 스텝으로 하기
            {
                self.stepCountWhileNotUsingGps += 1
            }
        }
    }
    
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let latestLocation: CLLocation = locations[locations.count - 1]
        
        if startLocation == nil {
            // 위치 트래킹을 시작하고 처음 데이터 몇개가 튐. 트래킹을 처음 시작할 때 보다 중단하고 다시 시작할 경우가 더 심하므로 이 경우는 15개째 부터 저장
            if ((distanceBetweenLocationArrayForSave.count == 0 || totalDistanceByGps==0) && dummyStartLocations.count >= 9) ||
            (distanceBetweenLocationArrayForSave.count > 0 && dummyStartLocations.count >= 14) {
                startLocation = latestLocation
            } else {
                dummyStartLocations.append(latestLocation)
            }
        }
        
        
        if let start = self.startLocation {
            let distanceBetween: CLLocationDistance = latestLocation.distanceFromLocation(start)
            let distanceDelta = distanceBetween - self.distanceBetweenLocation
            if //stepForCheck != self.stepCount ||
                (distanceDelta > 0 && distanceDelta>2)
            { // 거리 변화가 0보다 클 때(이동거리가 증가)만 업데이트 시켜주기
                //stepForCheck = self.stepCount
                self.distanceBetweenLocation = distanceBetween
            }
        }
        
        //        if UIApplication.sharedApplication().applicationState == .Background {
        //            print("background call")
        //        } else {
        //            print("foreground call")
        //        }
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if status == .AuthorizedWhenInUse || status == .AuthorizedAlways {
            locationManager.startUpdatingLocation()
            locationAuthorized = true
        } else {
            locationAuthorized = false
        }
        
        if let _didChangeAuthorization = didChangeAuthorization {
            _didChangeAuthorization(isAuthorized: locationAuthorized)
        }
    }
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        //locationFailedCount += 1
    }
    
    
}