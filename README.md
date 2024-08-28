# extractEndpoint_url_fromJsfiles
استخراج مسارات وروابط من ملفات الجافا سكربت باستخدام linkfinder &amp; golinkfinder

وتنسيقها بشكل مناسب وجاهز

طريقة التحميل

base tool: 
```
cd && git clone https://github.com/GerbenJavado/LinkFinder.git && cd LinkFinder && sudo python3 setup.py install && sudo pip3 install -r requirements.txt && cd && go install github.com/0xsha/GoLinkFinder@latest && cd && sudo apt-get install parallel -y
```

```
git clone https://github.com/mohaned2210/extractEndpoint_url_fromJsfiles.git
cd extractEndpoint_url_fromJsfiles/
chmod +x extract_link_fromJs.sh  
```

usage:
```
./extract_link_fromJs.sh -u /path/to/jsUrls.txt
```
![image](https://github.com/mohaned2210/extractEndpoint_url_fromJsfiles/assets/139042918/d00f9914-ab7e-4133-afd6-c6d9e8878417)
