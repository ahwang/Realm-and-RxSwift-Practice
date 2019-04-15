//
//  ViewController.swift
//  RealmTest
//
//  Created by Hwang, Andrew on 3/4/19.
//  Copyright © 2019 Hwang, Andrew. All rights reserved.
//

import UIKit
import RealmSwift
import RxSwift
import RxCocoa
import RxDataSources

final class Name: Object {
    @objc dynamic var text = ""
    @objc dynamic var subtext = ""
    @objc dynamic var completed = false
}

struct NameState: Comparable, IdentifiableType, Hashable {
    
    var identity: NameState { return self }
    
    var name: Name
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name.text)
        hasher.combine(name.subtext)
    }
    
    static func < (lhs: NameState, rhs: NameState) -> Bool {
        return lhs.name == rhs.name
    }
    
    init(_ name: Name) {
        self.name = name
    }
    
}

struct Section {
    var items: [Item]
}

extension Section : AnimatableSectionModelType {
    typealias Item = NameState
    var identity: String {
        return ""
    }
    
    init(original: Section, items: [Item]) {
        self = original
        self.items = items
    }
}

class ViewController: UITableViewController {
    
    let reuseID = "cell"
    let searchController = UISearchController(searchResultsController: nil)
    let disposeBag = DisposeBag()
    
    var token: NotificationToken?
    var notificationToken: NotificationToken?
    var realm: Realm!
    var searchValue: Variable<String> = Variable("")
    var filteredNames: Results<Name>?
    var dataSource: RxTableViewSectionedAnimatedDataSource<Section>?
    
    lazy var searchValueObserver: Observable<String> = self.searchValue.asObservable()
    
//    struct Constants {
//        static let INSTANCE_ADDRESS = "ahwang.us1.cloud.realm.io"
//        static let AUTH_URL = URL(string: "https://\(INSTANCE_ADDRESS)")!
//        static let REALM_URL = URL(string: "realms://\(INSTANCE_ADDRESS)/default")!
//    }
    

    override func viewDidLoad() {
        setupNavItem()
        //setupTable()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: reuseID)

        tableView.delegate = self
        tableView.dataSource = self
        
        setupSearch()
        setupRealm()
        setupObserver()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        SyncUser.current?.logOut()
    }
    
    func setupNavItem() {
        title = "Names"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addName))
    }
    
    func setupTable() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: reuseID)
        
        var nameList: [NameState] = []
        
        let dataSource = RxTableViewSectionedAnimatedDataSource<Section>(
            configureCell: { ds, tv, ip, item in
                
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: self.reuseID)
                if self.isFiltering() {
                    if (self.filteredNames?.count)! > ip.row {
                        let filteredName = self.filteredNames![ip.row].text
                        let filteredDescription = self.filteredNames![ip.row].subtext
                        let attrString = self.generateAttributedString(with: self.searchValue.value, targetString: filteredName)
                        let attrSubString = self.generateAttributedString(with: self.searchValue.value, targetString: filteredDescription)
                        cell.textLabel?.attributedText = attrString
                        cell.detailTextLabel?.attributedText = attrSubString
                    } else {
                        cell.textLabel?.attributedText = nil
                        cell.detailTextLabel?.attributedText = nil
                        cell.textLabel?.text = ""
                        cell.detailTextLabel?.text = ""
                    }
                } else {
                    cell.textLabel?.attributedText = nil
                    cell.detailTextLabel?.attributedText = nil
                    cell.textLabel?.text = item.name.text
                    cell.detailTextLabel?.text = item.name.subtext
                }
                
                return cell
            }
        )
        
        self.dataSource = dataSource
        
        
        dataSource.canEditRowAtIndexPath  = { dataSource, indexPath in
            return true
        }
        
        filteredNames?.forEach {
            let state = NameState.init($0)
            nameList.append(state)
        }
        
        let sections = [
            Section(items: nameList)
        ]
        
        Observable.just(sections)
            .bind(to: tableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)
        
        tableView.rx.itemDeleted
            .subscribe(onNext: { self.deleteItem(at: $0) })
            .disposed(by: disposeBag)
        
        tableView.rx.itemSelected
            .subscribe(onNext: { self.editItem(at: $0) })
            .disposed(by:disposeBag)
        
        tableView.rx.setDelegate(self)
            .disposed(by: disposeBag)
    }
    
    func setupSearch() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Names"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
        searchController.searchBar.rx.text
            .orEmpty
            .distinctUntilChanged()
            .debug()
            .bind(to: searchValue)
            .disposed(by: disposeBag)
    }
    
    func setupRealm() {
        self.realm = try! Realm()
    }
    
    func setupObserver() {
        searchValueObserver.subscribe(onNext: { (value) in
            
            if value != "" {
                let valArr = value.split(separator: " ")
                self.filteredNames = self.realm.objects(Name.self).filter("(text CONTAINS[c] '\(valArr.count > 1 ? (String(valArr[1])) : value)' OR (text CONTAINS[c] '\(valArr.count > 1 ? (String(valArr[1])) : value)' AND (text BEGINSWITH[c] '\(valArr.count > 1 ? String(valArr[1]).first! : value.first!)' OR text BEGINSWITH[c] '\(value.first!)'))) OR (subtext CONTAINS[c] '\(value)')").sorted(byKeyPath: "text", ascending: true)
                
            } else {
                 self.filteredNames = self.realm.objects(Name.self).sorted(byKeyPath: "text", ascending: true)
            }
            
            self.notificationToken?.invalidate()
            
            self.notificationToken = self.filteredNames?.observe({ (collectionEvent) in
                switch collectionEvent {
                case .initial:
                    self.tableView.reloadData()
                case .update(_, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    self.tableView.performBatchUpdates({
                        self.tableView.reloadRows(at: modifications.map { IndexPath(row: $0, section: 0) }, with: .fade)
                        self.tableView.insertRows(at: insertions.map { IndexPath(row: $0, section: 0) }, with: .fade)
                        self.tableView.deleteRows(at: deletions.map { IndexPath(row: $0, section: 0) }, with: .fade)
                    })
                default:
                    break
                }
            })
        }).disposed(by: disposeBag)
    }
    
    deinit {
        notificationToken?.invalidate()
    }
    
    func deleteItem(at indexPath: IndexPath) {
        let name = filteredNames![indexPath.row]
        
        try! realm.write {
            realm.delete(name)
        }
    }
    
    func editItem(at indexPath: IndexPath) {
        let alertController = UIAlertController(title: "Edit Name", message: "", preferredStyle: .alert)
        var alertTextField: UITextField!
        var alertSubTextField: UITextField!
        alertController.addTextField { textField in
            alertTextField = textField
            textField.text = "\(self.filteredNames![indexPath.row].text)"
        }
        alertController.addTextField { (textField) in
            alertSubTextField = textField
            textField.text = "\(self.filteredNames![indexPath.row].subtext)"
        }
        alertController.addAction(UIAlertAction(title: "Edit", style: .default) { _ in
            guard let text = alertTextField.text , !text.isEmpty else { return }
            guard let subtext = alertSubTextField.text , !subtext.isEmpty else { return }
            try! self.realm.write {
                //let newName = Name(value: ["text": text, "subtext": subtext])
                
                self.filteredNames![indexPath.row].text = text
                self.filteredNames![indexPath.row].subtext = subtext
                
                
            }
            
        })
        present(alertController, animated: true, completion: nil)
    }
    
    func writeToRealm(_ text: String, _ subtext: String) {
        try! self.realm.write {
            let newName = Name(value: ["text": text, "subtext": subtext])
            self.realm.add(newName)
        }
    }
    
    func searchBarIsEmpty() -> Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    
    func isFiltering() -> Bool {
        return searchController.isActive && !searchBarIsEmpty()
    }
    
    @objc func addName() {
        let alertController = UIAlertController(title: "New Name", message: "Enter a Name", preferredStyle: .alert)
        var alertTextField: UITextField!
        var alertSubTextField: UITextField!
        alertController.addTextField { textField in
            alertTextField = textField
            textField.placeholder = "Name"
        }
        alertController.addTextField { (textField) in
            alertSubTextField = textField
            textField.placeholder = "Description"
        }
        alertController.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            guard let text = alertTextField.text , !text.isEmpty else { return }
            guard let subtext = alertSubTextField.text , !subtext.isEmpty else { return }
            self.writeToRealm(text, subtext)
        })
        present(alertController, animated: true, completion: nil)
    }
    
    func generateAttributedString(with searchTerm: String, targetString: String) -> NSAttributedString? {
        let attributedString = NSMutableAttributedString(string: targetString)
        do {
            let regex = try NSRegularExpression(pattern: searchTerm, options: .caseInsensitive)
            let range = NSRange(location: 0, length: targetString.utf16.count)
            for match in regex.matches(in: targetString, options: .withTransparentBounds, range: range) {
                attributedString.addAttribute(NSAttributedString.Key.backgroundColor, value: UIColor.yellow, range: match.range)
            }
            return attributedString
        } catch _ {
            NSLog("Error creating regular expresion")
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredNames?.count ?? 0
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: reuseID)
        if isFiltering() {
            let filteredName = filteredNames![indexPath.row].text
            let filteredDescription = filteredNames![indexPath.row].subtext
            let attrString = generateAttributedString(with: searchValue.value, targetString: filteredName)
            let attrSubString = generateAttributedString(with: searchValue.value, targetString: filteredDescription)
            cell.textLabel?.attributedText = attrString
            cell.detailTextLabel?.attributedText = attrSubString
        } else {
            cell.textLabel?.attributedText = nil
            cell.textLabel?.text = filteredNames![indexPath.row].text
            cell.detailTextLabel?.text = filteredNames![indexPath.row].subtext
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let name = filteredNames![indexPath.row]
        try! realm.write {
            realm.delete(name)
        }
    }
}
