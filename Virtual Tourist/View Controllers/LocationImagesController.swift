//
//  LocationImagesController.swift
//  Location Images
//
//  Created by Elina Mansurova on 2020-10-21.
//

import Foundation
import MapKit
import CoreData

class LocationImagesController: UIViewController, MKMapViewDelegate, UICollectionViewDelegate, UICollectionViewDataSource {
   
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var addCollection: UIButton!
    @IBOutlet weak var noImagesFound: UILabel!
    @IBOutlet weak var newCollection: UIButton!
    
    var photos: [Photo] = []
    private let reuseIdentifier = "ImageCell"
    var coordinates: CLLocationCoordinate2D?
    
    var dataController: DataController!
    
    var selectedToDelete: [Int] = [] {
        didSet {
            if selectedToDelete.isEmpty {
                newCollection.setTitle("New Collection", for: .normal)
            } else {
                newCollection.setTitle("Delete selected pictures", for: .normal)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        newCollection?.isEnabled = false
        focusOnMap()
        if checkIfThereAreSavedImages() {
            loadPhotoFromDataBase()
            newCollection?.isEnabled = true
        } else {
            downloadImages()
        }
        noImagesFound.isHidden = true
    }
    
    @IBAction func didTapNewCollection(_ sender: Any) {
        if selectedToDelete.isEmpty {
            photos = []
            pinFromLocation()?.removeFromPhotos(pinFromLocation()!.photos!)
            collectionView.reloadData()
            downloadImages()
        } else {
            showConfirmationForDelete(title: "Delete selected photos",
                                      message: "Are you sure you want to delete selected photos?") {
                self.deletePhotosFromData()
            }
        }
    }
    
    func deletePhotosFromData() {
        guard let pin = pinFromLocation(), let coreDataPhotos = pin.photos?.array as? [SavedPhoto] else {
            return
        }
        for index in selectedToDelete {
            photos.remove(at: index)
            let savedPhotoToRemove = coreDataPhotos[index]
            pin.removeFromPhotos(savedPhotoToRemove)
        }
        try? dataController.viewContext.save()
        collectionView.deleteItems(at: selectedToDelete.map { IndexPath(item: $0, section: 0) })
        selectedToDelete = []
    }
    
    func deleteItem(at indexPath: IndexPath) {
        photos.remove(at: indexPath.row)
        collectionView.reloadData()
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        cell?.isSelected = true
        selectedToDelete.append(indexPath.row)
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        cell?.isSelected = false
        if let indexToRemove = selectedToDelete.firstIndex(where: { $0 == indexPath.row }) {
            selectedToDelete.remove(at: indexToRemove)
        }
    }
    
    func focusOnMap() {
        guard let coordinates = coordinates else {
            return
        }
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinates
        
        mapView.addAnnotation(annotation)
        let regionFocus = MKCoordinateRegion(center: coordinates, latitudinalMeters: 50000, longitudinalMeters: 50000)
        mapView.setRegion(regionFocus, animated: true)
    }
    
    fileprivate func checkIfThereAreSavedImages() -> Bool {
        if let pin = pinFromLocation() {
            return pin.photos?.count != 0
        }
        return false
    }
    
    func pinFromLocation() -> Pin? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Pin")
        guard let coordinates = coordinates else {
            return nil
        }
        request.predicate = NSPredicate(format: "latitude == %lf && longitude == %lf", coordinates.latitude, coordinates.longitude)
        return try? dataController.viewContext.fetch(request).first as? Pin
    }
    
    func loadPhotoFromDataBase() {
        guard let pin = pinFromLocation(), let photos = pin.photos?.array as? [SavedPhoto] else {
            return
        }
        for photo in photos {
            if let imageData = photo.imageData {
                var photo = Photo()
                photo.image = UIImage(data: imageData)
                self.photos.append(photo)
            }
        }
        noImagesFound.superview?.removeFromSuperview()
        collectionView.reloadData()
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    fileprivate func savePhotoToCoreData(_ image: UIImage?) {
        let savedPhoto = SavedPhoto(context: self.dataController.viewContext)
        savedPhoto.imageData = image?.jpegData(compressionQuality: 1.0)
        self.pinFromLocation()?.addToPhotos(savedPhoto)
        do {
            try self.dataController.viewContext.save()
        } catch {
            print(error)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ImageCell
        let photo = self.photos[indexPath.row]
        if let image = photo.image {
            cell.imageView.image = image
        } else {
            cell.imageView.isHidden = true
            cell.activityIndicator.startAnimating()
            cell.imageView.loadFromURL(photoUrl: photo.urlToDownload) { [weak self] image in
                guard let self = self else { return }
                self.savePhotoToCoreData(image)
                cell.imageView.isHidden = false
                cell.activityIndicator.stopAnimating()
            }
        }
        return cell
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { print("no mkpointannotaions"); return nil }
        
        let reuseId = "pin"
        var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKPinAnnotationView
        
        if pinView == nil {
            pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            pinView!.canShowCallout = true
            pinView!.rightCalloutAccessoryView = UIButton(type: .infoDark)
            pinView!.pinTintColor = UIColor.black
        }
        else {
            pinView!.annotation = annotation
        }
        return pinView
    }
    
    func downloadImages() {
        guard let coordinates = coordinates else {
            return
        }
        Client.getCollection(coordinate: coordinates) { (result) in
            switch result {
            case .success(let response):
                self.photos = response.photos.photo
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                    if self.photos.isEmpty {
                        self.noImagesFound?.isHidden = false
                    } else {
                        self.noImagesFound?.superview?.removeFromSuperview()
                    }
                }
            case .failure:
                self.noImagesFound?.isHidden = false
            }
            DispatchQueue.main.async {
                self.newCollection?.isEnabled = true
            }
        }
    }
}

extension LocationImagesController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let space: CGFloat = 3.0
        let dimension = (view.frame.size.width - (2 * space)) / 3.0
        let size = CGSize(width:dimension, height: dimension)
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 3.0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout
                            collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 3.0
    }
}


