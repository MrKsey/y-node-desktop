package desktop

import (
	"encoding/json"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

// country is one entry of the public peer list. The list groups peers by a
// directory named after the country, so the parser only has a slug such as
// "united-states"; the table below turns it into a display name, a flag and a
// rough centre, which is all the ranking needs.
type country struct {
	Slug string
	Code string
	Name string
	Lat  float64
	Lon  float64
}

var countries = parseCountries(`
afghanistan|AF|Afghanistan|33.94|67.71
albania|AL|Albania|41.15|20.17
algeria|DZ|Algeria|28.03|1.66
andorra|AD|Andorra|42.55|1.60
angola|AO|Angola|-11.20|17.87
argentina|AR|Argentina|-38.42|-63.62
armenia|AM|Armenia|40.07|45.04
australia|AU|Australia|-25.27|133.78
austria|AT|Austria|47.52|14.55
azerbaijan|AZ|Azerbaijan|40.14|47.58
bahrain|BH|Bahrain|26.07|50.55
bangladesh|BD|Bangladesh|23.68|90.36
belarus|BY|Belarus|53.71|27.95
belgium|BE|Belgium|50.50|4.47
bolivia|BO|Bolivia|-16.29|-63.59
bosnia-and-herzegovina|BA|Bosnia and Herzegovina|43.92|17.68
botswana|BW|Botswana|-22.33|24.68
brazil|BR|Brazil|-14.24|-51.93
brunei|BN|Brunei|4.54|114.73
bulgaria|BG|Bulgaria|42.73|25.49
cambodia|KH|Cambodia|12.57|104.99
cameroon|CM|Cameroon|7.37|12.35
canada|CA|Canada|56.13|-106.35
chile|CL|Chile|-35.68|-71.54
china|CN|China|35.86|104.20
colombia|CO|Colombia|4.57|-74.30
costa-rica|CR|Costa Rica|9.75|-83.75
croatia|HR|Croatia|45.10|15.20
cuba|CU|Cuba|21.52|-77.78
cyprus|CY|Cyprus|35.13|33.43
czechia|CZ|Czechia|49.82|15.47
denmark|DK|Denmark|56.26|9.50
dominican-republic|DO|Dominican Republic|18.74|-70.16
ecuador|EC|Ecuador|-1.83|-78.18
egypt|EG|Egypt|26.82|30.80
el-salvador|SV|El Salvador|13.79|-88.90
estonia|EE|Estonia|58.60|25.01
ethiopia|ET|Ethiopia|9.15|40.49
finland|FI|Finland|61.92|25.75
france|FR|France|46.23|2.21
georgia|GE|Georgia|42.32|43.36
germany|DE|Germany|51.17|10.45
ghana|GH|Ghana|7.95|-1.02
greece|GR|Greece|39.07|21.82
guatemala|GT|Guatemala|15.78|-90.23
honduras|HN|Honduras|15.20|-86.24
hong-kong|HK|Hong Kong|22.32|114.17
hungary|HU|Hungary|47.16|19.50
iceland|IS|Iceland|64.96|-19.02
india|IN|India|20.59|78.96
indonesia|ID|Indonesia|-0.79|113.92
iran|IR|Iran|32.43|53.69
iraq|IQ|Iraq|33.22|43.68
ireland|IE|Ireland|53.41|-8.24
israel|IL|Israel|31.05|34.85
italy|IT|Italy|41.87|12.57
jamaica|JM|Jamaica|18.11|-77.30
japan|JP|Japan|36.20|138.25
jordan|JO|Jordan|30.59|36.24
kazakhstan|KZ|Kazakhstan|48.02|66.92
kenya|KE|Kenya|-0.02|37.91
kuwait|KW|Kuwait|29.31|47.48
kyrgyzstan|KG|Kyrgyzstan|41.20|74.77
laos|LA|Laos|19.86|102.50
latvia|LV|Latvia|56.88|24.60
lebanon|LB|Lebanon|33.85|35.86
libya|LY|Libya|26.34|17.23
lithuania|LT|Lithuania|55.17|23.88
luxembourg|LU|Luxembourg|49.82|6.13
macau|MO|Macau|22.20|113.54
madagascar|MG|Madagascar|-18.77|46.87
malaysia|MY|Malaysia|4.21|101.98
maldives|MV|Maldives|3.20|73.22
malta|MT|Malta|35.94|14.38
mexico|MX|Mexico|23.63|-102.55
moldova|MD|Moldova|47.41|28.37
mongolia|MN|Mongolia|46.86|103.85
montenegro|ME|Montenegro|42.71|19.37
morocco|MA|Morocco|31.79|-7.09
mozambique|MZ|Mozambique|-18.67|35.53
myanmar|MM|Myanmar|21.91|95.96
nepal|NP|Nepal|28.39|84.12
netherlands|NL|Netherlands|52.13|5.29
new-zealand|NZ|New Zealand|-40.90|174.89
nicaragua|NI|Nicaragua|12.87|-85.21
nigeria|NG|Nigeria|9.08|8.68
north-macedonia|MK|North Macedonia|41.61|21.75
norway|NO|Norway|60.47|8.47
oman|OM|Oman|21.51|55.92
pakistan|PK|Pakistan|30.38|69.35
palestine|PS|Palestine|31.95|35.23
panama|PA|Panama|8.54|-80.78
paraguay|PY|Paraguay|-23.44|-58.44
peru|PE|Peru|-9.19|-75.02
philippines|PH|Philippines|12.88|121.77
poland|PL|Poland|51.92|19.15
portugal|PT|Portugal|39.40|-8.22
puerto-rico|PR|Puerto Rico|18.22|-66.59
qatar|QA|Qatar|25.35|51.18
romania|RO|Romania|45.94|24.97
russia|RU|Russia|61.52|105.32
rwanda|RW|Rwanda|-1.94|29.87
saudi-arabia|SA|Saudi Arabia|23.89|45.08
senegal|SN|Senegal|14.50|-14.45
serbia|RS|Serbia|44.02|21.01
singapore|SG|Singapore|1.35|103.82
slovakia|SK|Slovakia|48.67|19.70
slovenia|SI|Slovenia|46.15|14.99
somalia|SO|Somalia|5.15|46.20
south-africa|ZA|South Africa|-30.56|22.94
south-korea|KR|South Korea|35.91|127.77
spain|ES|Spain|40.46|-3.75
sri-lanka|LK|Sri Lanka|7.87|80.77
sudan|SD|Sudan|12.86|30.22
sweden|SE|Sweden|60.13|18.64
switzerland|CH|Switzerland|46.82|8.23
syria|SY|Syria|34.80|38.99
taiwan|TW|Taiwan|23.70|120.96
tajikistan|TJ|Tajikistan|38.86|71.28
tanzania|TZ|Tanzania|-6.37|34.89
thailand|TH|Thailand|15.87|100.99
tunisia|TN|Tunisia|33.89|9.54
turkey|TR|Turkey|38.96|35.24
turkmenistan|TM|Turkmenistan|38.97|59.56
uganda|UG|Uganda|1.37|32.29
ukraine|UA|Ukraine|48.38|31.17
united-arab-emirates|AE|United Arab Emirates|23.42|53.85
united-kingdom|GB|United Kingdom|55.38|-3.44
united-states|US|United States|37.09|-95.71
uruguay|UY|Uruguay|-32.52|-55.77
uzbekistan|UZ|Uzbekistan|41.38|64.59
venezuela|VE|Venezuela|6.42|-66.59
vietnam|VN|Vietnam|14.06|108.28
zambia|ZM|Zambia|-13.13|27.85
zimbabwe|ZW|Zimbabwe|-19.02|29.15
`)

// parseCountries reads the compact table above: one country per line, the
// fields separated by a vertical bar.
func parseCountries(raw string) []country {
	var out []country
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Split(line, "|")
		if len(fields) != 5 {
			continue
		}
		lat, err := strconv.ParseFloat(fields[3], 64)
		if err != nil {
			continue
		}
		lon, err := strconv.ParseFloat(fields[4], 64)
		if err != nil {
			continue
		}
		out = append(out, country{
			Slug: fields[0],
			Code: fields[1],
			Name: fields[2],
			Lat:  lat,
			Lon:  lon,
		})
	}
	return out
}

// Aliases the peer list has used for the same country.
var slugAliases = map[string]string{
	"czech-republic":    "czechia",
	"great-britain":     "united-kingdom",
	"uk":                "united-kingdom",
	"usa":               "united-states",
	"korea":             "south-korea",
	"republic-of-korea": "south-korea",
	"uae":               "united-arab-emirates",
}

var (
	bySlug = map[string]country{}
	byCode = map[string]country{}
)

func init() {
	for _, item := range countries {
		bySlug[item.Slug] = item
		byCode[item.Code] = item
	}
}

func countryBySlug(slug string) (country, bool) {
	normalised := strings.ToLower(strings.TrimSpace(slug))
	item, ok := bySlug[normalised]
	if ok {
		return item, true
	}
	alias, ok := slugAliases[normalised]
	if !ok {
		return country{}, false
	}
	item, ok = bySlug[alias]
	return item, ok
}

func countryName(slug string) string {
	if item, ok := countryBySlug(slug); ok {
		return item.Name
	}
	if slug == "" {
		return "Unknown"
	}
	parts := strings.Split(slug, "-")
	for index, part := range parts {
		if part == "" {
			continue
		}
		parts[index] = strings.ToUpper(part[:1]) + part[1:]
	}
	return strings.Join(parts, " ")
}

func countryFlag(slug string) string {
	item, ok := countryBySlug(slug)
	if !ok || len(item.Code) != 2 {
		return ""
	}
	first := rune(item.Code[0]-'A') + 0x1F1E6
	second := rune(item.Code[1]-'A') + 0x1F1E6
	if first < 0x1F1E6 || first > 0x1F1FF || second < 0x1F1E6 || second > 0x1F1FF {
		return ""
	}
	return string([]rune{first, second})
}

// distanceKm is the great-circle distance between two points.
func distanceKm(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadius = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * earthRadius * math.Asin(math.Min(1, math.Sqrt(a)))
}

// geoLocation is where the user is, as far as GeoIP can tell.
type geoLocation struct {
	CountryCode string  `json:"countryCode"`
	CountrySlug string  `json:"countrySlug"`
	CountryName string  `json:"countryName"`
	Flag        string  `json:"flag"`
	City        string  `json:"city"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	Source      string  `json:"source"`
}

// lookupGeo asks a public GeoIP service where this device is. Both providers
// are keyless; ipinfo.io answers over HTTPS and is tried first.
func lookupGeo() (geoLocation, bool) {
	client := &http.Client{Timeout: 8 * time.Second}
	for _, endpoint := range []string{
		"https://ipinfo.io/json",
		"http://ip-api.com/json/?fields=status,country,countryCode,city,lat,lon",
	} {
		response, err := client.Get(endpoint)
		if err != nil {
			continue
		}
		var payload map[string]any
		decodeErr := json.NewDecoder(response.Body).Decode(&payload)
		response.Body.Close()
		if decodeErr != nil || response.StatusCode != http.StatusOK {
			continue
		}
		if status, _ := payload["status"].(string); status != "" && status != "success" {
			continue
		}
		code, _ := payload["countryCode"].(string)
		if code == "" {
			code, _ = payload["country"].(string)
		}
		code = strings.ToUpper(strings.TrimSpace(code))
		if len(code) != 2 {
			continue
		}
		item, ok := byCode[code]
		if !ok {
			continue
		}
		result := geoLocation{
			CountryCode: code,
			CountrySlug: item.Slug,
			CountryName: item.Name,
			Flag:        countryFlag(item.Slug),
			City:        stringValue(payload["city"]),
			Lat:         item.Lat,
			Lon:         item.Lon,
			Source:      "ipinfo.io",
		}
		if strings.Contains(endpoint, "ip-api") {
			result.Source = "ip-api.com"
		}
		if loc, _ := payload["loc"].(string); loc != "" {
			parts := strings.Split(loc, ",")
			if len(parts) > 0 {
				result.Lat = floatValue(parts[0], result.Lat)
			}
			if len(parts) > 1 {
				result.Lon = floatValue(parts[1], result.Lon)
			}
		}
		if lat, ok := payload["lat"].(float64); ok {
			result.Lat = lat
		}
		if lon, ok := payload["lon"].(float64); ok {
			result.Lon = lon
		}
		return result, true
	}
	return geoLocation{}, false
}

func stringValue(value any) string {
	text, _ := value.(string)
	return strings.TrimSpace(text)
}

// lookupGeoAddress places one address instead of the device. It is used for
// the exit node: the peer link carries the server address, and the flag on the
// tunnel screen shows where that server is.
func lookupGeoAddress(address string) (geoLocation, bool) {
	address = strings.TrimSpace(address)
	if address == "" {
		return geoLocation{}, false
	}
	client := &http.Client{Timeout: 8 * time.Second}
	for _, endpoint := range []string{
		"https://ipinfo.io/" + address + "/json",
		"http://ip-api.com/json/" + address + "?fields=status,country,countryCode,city,lat,lon",
	} {
		response, err := client.Get(endpoint)
		if err != nil {
			continue
		}
		var payload map[string]any
		decodeErr := json.NewDecoder(response.Body).Decode(&payload)
		response.Body.Close()
		if decodeErr != nil || response.StatusCode != http.StatusOK {
			continue
		}
		if status, _ := payload["status"].(string); status != "" && status != "success" {
			continue
		}
		code, _ := payload["countryCode"].(string)
		if code == "" {
			code, _ = payload["country"].(string)
		}
		code = strings.ToUpper(strings.TrimSpace(code))
		if len(code) != 2 {
			continue
		}
		item, ok := byCode[code]
		if !ok {
			continue
		}
		return geoLocation{
			CountryCode: code,
			CountrySlug: item.Slug,
			CountryName: item.Name,
			Flag:        countryFlag(item.Slug),
			City:        stringValue(payload["city"]),
			Lat:         item.Lat,
			Lon:         item.Lon,
			Source:      "geoip",
		}, true
	}
	return geoLocation{}, false
}

func floatValue(value string, fallback float64) float64 {
	parsed, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
	if err != nil {
		return fallback
	}
	return parsed
}

// countryCounts summarises the catalogue for the filter of the Peers page.
type countryCount struct {
	Slug  string `json:"slug"`
	Name  string `json:"name"`
	Flag  string `json:"flag"`
	Count int    `json:"count"`
}

func countryCountsOf(peers []CatalogPeer) []countryCount {
	counts := map[string]int{}
	for _, peer := range peers {
		if peer.Country == "" {
			continue
		}
		counts[peer.Country]++
	}
	out := make([]countryCount, 0, len(counts))
	for slug, count := range counts {
		out = append(out, countryCount{
			Slug:  slug,
			Name:  countryName(slug),
			Flag:  countryFlag(slug),
			Count: count,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}
