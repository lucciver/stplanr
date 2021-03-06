#' Do the intersections between two geometries create lines?
#'
#' This is a function required in [overline()]. It identifies
#' whether sets of lines overlap (beyond shared points) or
#' not.
#'
#' @param g1 A spatial object
#' @param g2 A spatial object
#' @family rnet
#' @export
#' @examples
#' \dontrun{
#' rnet <- overline(routes_fast[c(2, 3, 22), ], attrib = "length")
#' plot(rnet)
#' lines(routes_fast[22, ], col = "red") # line without overlaps
#' islines(routes_fast[2, ], routes_fast[3, ])
#' islines(routes_fast[2, ], routes_fast[22, ])
#' # sf implementation
#' islines(routes_fast_sf[2, ], routes_fast_sf[3, ])
#' islines(routes_fast_sf[2, ], routes_fast_sf[22, ])
#' }
islines <- function(g1, g2) {
  UseMethod("islines")
}
islines.Spatial <- function(g1, g2) {
  ## return TRUE if geometries intersect as lines, not points
  inherits(rgeos::gIntersection(g1, g2), "SpatialLines")
}
islines.sf <- function(g1, g2) {
  sf::st_geometry_type(sf::st_intersection(sf::st_geometry(g1), sf::st_geometry(g2))) == "MULTILINESTRING"
}

#' Function to split overlapping SpatialLines into segments
#'
#' Divides SpatialLinesDataFrame objects into separate Lines.
#' Each new Lines object is the aggregate of a single number
#' of aggregated lines.
#'
#' @param sl SpatialLinesDataFrame with overlapping Lines to split by
#' number of overlapping features.
#' @param buff_dist A number specifying the distance in meters of the buffer to be used to crop lines before running the operation.
#' If the distance is zero (the default) touching but non-overlapping lines may be aggregated.
#' @family rnet
#' @export
#' @examples
#' lib_versions <- sf::sf_extSoftVersion()
#' lib_versions
#' # fails on some systems (with early versions of PROJ)
#' if(lib_versions[3] >= "6.3.1") {
#'   sl <- routes_fast_sf[2:4, ]
#'   rsec <- gsection(sl)
#'   length(rsec) # sections
#'   plot(rsec, col = seq(length(rsec)))
#'   rsec <- gsection(sl, buff_dist = 50)
#'   length(rsec) # 4 features: issue
#'   plot(rsec, col = seq(length(rsec)))
#'   # dont test due to issues with sp classes on some set-ups
#'   # sl <- routes_fast[2:4, ]
#'   # rsec <- gsection(sl)
#'   # rsec_buff <- gsection(sl, buff_dist = 1)
#'   # plot(sl[1], lwd = 9, col = 1:nrow(sl))
#'   # plot(rsec, col = 5 + (1:length(rsec)), add = TRUE, lwd = 3)
#'   # plot(rsec_buff, col = 5 + (1:length(rsec_buff)), add = TRUE, lwd = 3)
#' }
gsection <- function(sl, buff_dist = 0) {
  UseMethod("gsection")
}
#' @export
gsection.Spatial <- function(sl, buff_dist = 0) {
  if (buff_dist > 0) {
    sl <- geo_toptail(sl, toptail_dist = buff_dist)
  }
  overlapping <- rgeos::gOverlaps(sl, byid = T)
  u <- rgeos::gUnion(sl, sl)
  u_merged <- rgeos::gLineMerge(u)
  sp::disaggregate(u_merged)
}
#' @export
gsection.sf <- function(sl, buff_dist = 0) {
  if (buff_dist > 0) {
    sl <- geo_toptail(sl, toptail_dist = buff_dist)
  }

  u <- sf::st_union(sl)
  u_merged <- sf::st_line_merge(u)
  u_disag <- sf::st_cast(u_merged, "LINESTRING")

  u_disag
}
#' Label SpatialLinesDataFrame objects
#'
#' This function adds labels to lines plotted using base graphics. Largely
#' for illustrative purposes, not designed for publication-quality
#' graphics.
#'
#' @param sl A SpatialLinesDataFrame with overlapping elements
#' @param attrib A text string corresponding to a named variable in `sl`
#'
#' @author Barry Rowlingson
#' @family rnet
#'
#' @export
lineLabels <- function(sl, attrib) {
  text(sp::coordinates(
    rgeos::gCentroid(sl, byid = TRUE)
  ), labels = sl[[attrib]])
}

#' Convert series of overlapping lines into a route network
#'
#' This function takes a series of overlapping lines and converts them into a
#' single route network.
#'
#' The function can be used to estimate the amount of transport 'flow' at the
#' route segment level based on input datasets from routing services, for
#' example linestring geometries created with the `route()` function.
#'
#' @param attrib A character vector corresponding to the variables in `sl$` on
#'   which the function(s) will operate.
#' @param fun The function(s) used to aggregate the grouped values (default:
#'   sum). If length of `fun` is smaller than `attrib` then the functions are
#'   repeated for subsequent attributes.
#' @param na.zero Sets whether aggregated values with a value of zero are
#'   removed.
#' @param ... Arguments passed to `overline2`
#' @inheritParams gsection
#' @inheritParams overline2
#' @author Barry Rowlingson
#' @references 
#' Morgan M and Lovelace R (2020). Travel flow aggregation: Nationally scalable methods
#' for interactive and online visualisation of transport behaviour at the road network level.
#' Environment and Planning B: Urban Analytics and City Science. July 2020.
#' [doi:10.1177/2399808320942779](https://doi.org/10.1177%2F2399808320942779)
#'
#' Rowlingson, B (2015). Overlaying lines and aggregating their values for overlapping
#' segments. Reproducible question from <https://gis.stackexchange.com>. See
#' <https://gis.stackexchange.com/questions/139681/overlaying-lines-and-aggregating-their-values-for-overlapping-segments>.
#'
#'
#' @details The `overline()` function breaks each line into many straight
#' segments and then looks for duplicated segments. Attributes are summed for
#' all duplicated segments, and if simplify is TRUE the segments with identical
#' attributes are recombined into linestrings.
#'
#' The following arguments only apply to the `sf` implementation of `overline()`:
#'
#' - `ncores`, the number of cores to use in parallel processing
#' - `simplify`, should the final segments be converted back into longer lines? The default
#' setting.
#' - `regionalise` the threshold number of rows above which
#' regionalisation is used (see details).
#'
#'
#' For `sf` objects Regionalisation breaks the dataset into a 10 x 10 grid and
#' then performed the simplification across each grid. This significantly
#' reduces computation time for large datasets, but slightly increases the final
#' file size. For smaller datasets it increases computation time slightly but
#' reduces memory usage and so may also be useful.
#'
#' A known limitation of this method is that overlapping segments of different
#' lengths are not aggregated. This can occur when lines stop halfway down a
#' road. Typically these errors are small, but some artefacts may remain within
#' the resulting data.
#'
#' For very large datasets nrow(x) > 1000000, memory usage can be significant.
#' In these cases is is possible to overline subsets of the dataset, rbind the
#' results together, and then overline again, to produce a final result.
#'
#' Multicore support is only enabled for the regionalised simplification stage
#' as it does not help with other stages.
#'
#' @family rnet
#' @export
#' @examples
#'
#' sl <- routes_fast_sf[2:4, ]
#' class(sl)
#' class(sl$geometry)
#' overline(sl = sl, attrib = "length")
#' rnet_sf <- overline(sl = sl, attrib = "length", quiet = FALSE)
#' plot(rnet_sf, lwd = rnet_sf$length / mean(rnet_sf$length))
#'
#' # legacy implementation based on sp data
#' # sl <- routes_fast[2:4, ]
#' # rnet1 <- overline(sl = sl, attrib = "length")
#' # rnet2 <- overline(sl = sl, attrib = "length", buff_dist = 1)
#' # plot(rnet1, lwd = rnet1$length / mean(rnet1$length))
#' # plot(rnet2, lwd = rnet2$length / mean(rnet2$length))
overline <- function(sl,
                     attrib,
                     fun = sum,
                     na.zero = FALSE,
                     buff_dist = 0,
                     ...) {
  UseMethod("overline")
}
#' @export
overline.sf <- function(sl, attrib, fun = sum, na.zero = FALSE, buff_dist = 0, ...) {
  overline2(sl,
    attrib,
    ncores = 1,
    simplify = TRUE,
    regionalise = 1e5,
    ...
  )
}
#' @export
overline.Spatial <- function(sl, attrib, fun = sum, na.zero = FALSE, buff_dist = 0, ...) {
  fun <- c(fun)
  if (length(fun) < length(attrib)) {
    fun <- rep(c(fun), length.out = length(attrib))
  }

  sl_sp <- as(sl, "SpatialLines")

  ## get the line sections that make the network
  slu <- gsection(sl, buff_dist = buff_dist)
  ## overlay network with routes
  overs <- sp::over(slu, sl_sp, returnList = TRUE)
  ## overlay is true if end points overlay, so filter them out:
  overs <- lapply(1:length(overs), function(islu) {
    Filter(function(isl) {
      islines(sl_sp[isl, ], slu[islu, ])
    }, overs[[islu]])
  })
  ## now aggregate the required attribibute using fun():
  # aggs = sapply(overs, function(os){fun(sl[[attrib]][os])})
  aggs <- setNames(
    as.data.frame(
      lapply(
        1:length(attrib),
        function(y, overs, attribs, aggfuns) {
          sapply(overs, function(os, attrib, fun2) {
            fun2(sl[[attrib]][os])
          },
          attrib = attribs[y],
          fun2 = aggfuns[[y]]
          )
        },
        overs,
        attrib,
        fun
      )
    ),
    attrib
  )

  ## make a sl with the named attribibute:
  sl <- sp::SpatialLinesDataFrame(slu, aggs)
  # names(sl) = attrib

  ## remove lines with attribute values of zero
  if (na.zero) {
    sl <- sl[sl[[attrib]] > 0, ]
  }

  sl
}

#' Aggregate flows so they become non-directional (by geometry - the slow way)
#'
#' Flow data often contains movement in two directions: from point A to point B
#' and then from B to A. This can be problematic for transport planning, because
#' the magnitude of flow along a route can be masked by flows the other direction.
#' If only the largest flow in either direction is captured in an analysis, for
#' example, the true extent of travel will by heavily under-estimated for
#' OD pairs which have similar amounts of travel in both directions.
#' Flows in both direction are often represented by overlapping lines with
#' identical geometries (see [flowlines()]) which can be confusing
#' for users and are difficult to plot.
#'
#' This function aggregates directional flows into non-directional flows,
#' potentially halving the number of lines objects and reducing the number
#' of overlapping lines to zero.
#'
#' @param x A dataset containing linestring geometries
#' @param attrib A text string containing the name of the line's attribute to
#' aggregate or a numeric vector of the columns to be aggregated
#'
#' @return `onewaygeo` outputs a SpatialLinesDataFrame with single lines
#' and user-selected attribute values that have been aggregated. Only lines
#' with a distance (i.e. not intra-zone flows) are included
#' @family lines
#' @export
#' @examples
#' plot(flowlines[1:30, ], lwd = flowlines$On.foot[1:30])
#' singlines <- onewaygeo(flowlines[1:30, ], attrib = which(names(flowlines) == "On.foot"))
#' plot(singlines, lwd = singlines$On.foot / 2, col = "red", add = TRUE)
#' \dontrun{
#' plot(flowlines, lwd = flowlines$All / 10)
#' singlelines <- onewaygeo(flowlines, attrib = 3:14)
#' plot(singlelines, lwd = singlelines$All / 20, col = "red", add = TRUE)
#' sum(singlelines$All) == sum(flowlines$All)
#' nrow(singlelines)
#' singlelines_sf <- onewaygeo(flowlines_sf, attrib = 3:14)
#' sum(singlelines_sf$All) == sum(flowlines_sf$All)
#' summary(singlelines$All == singlelines_sf$All)
#' }
onewaygeo <- function(x, attrib) {
  UseMethod("onewaygeo")
}
#' @export
onewaygeo.sf <- function(x, attrib) {
  geq <- sf::st_equals(x, x, sparse = FALSE) | sf::st_equals_exact(x, x, sparse = FALSE, par = 0.0)
  sel1 <- !duplicated(geq) # repeated rows
  x$matching_rows <- apply(geq, 1, function(x) paste0(formatC(which(x), width = 4, format = "d", flag = 0), collapse = "-"))

  singlelines <- stats::aggregate(x[attrib], list(x$matching_rows), FUN = sum)

  return(singlelines)
}
#' @export
onewaygeo.Spatial <- function(x, attrib) {
  geq <- rgeos::gEquals(x, x, byid = TRUE) | rgeos::gEqualsExact(x, x, byid = TRUE)
  sel1 <- !duplicated(geq) # repeated rows
  singlelines <- x[sel1, ]
  non_numeric_cols <- which(!sapply(x@data, is.numeric))
  keeper_cols <- sort(unique(c(non_numeric_cols, attrib)))

  singlelines@data[, attrib] <- (matrix(
    unlist(
      lapply(
        apply(geq, 1, function(x) {
          which(x == TRUE)
        }),
        function(y, x) {
          colSums(x[y, attrib]@data)
        }, x
      )
    ),
    nrow = nrow(x),
    byrow = TRUE
  ))[sel1, ]

  singlelines@data <- singlelines@data[keeper_cols]

  return(singlelines)
}

#' Convert series of overlapping lines into a route network (new method)
#'
#' @description This function is intended as a replacement for overline() and is significantly faster
#' especially on large datasets. However, it also uses more memory.
#'
#' @param sl A spatial object representing routes on a transport network
#' @param attrib character, column names in sl to be summed
#' @param ncores integer, how many cores to use in parallel processing, default = 1
#' @param simplify logical, if TRUE group final segments back into lines, default = TRUE
#' @param regionalise integer, during simplification regonalisation is used if the number of segments exceeds this value
#' @param quiet Should the the function omit messages? `NULL` by default,
#' which means the output will only be shown if `sl` has more than 1000 rows.
#' @family rnet
#' @author Malcolm Morgan
#' @export
#' @return An `sf` object representing a route network
#' @rdname overline
overline2 <- function(sl, attrib, ncores = 1, simplify = TRUE, regionalise = 1e5, quiet = NULL) {
  if (!"sfc_LINESTRING" %in% class(sf::st_geometry(sl))) {
    stop("Only LINESTRING is supported")
  }
  if (any(c("1", "2", "3", "4", "grid") %in% attrib)) {
    stop("1, 2, 3, 4, grid are not a permitted column names, please rename that column")
  }
  if (is.null(quiet)) {
    quiet <- ifelse(nrow(sl) < 1000, TRUE, FALSE)
  }
  sl <- sf::st_zm(sl)
  sl <- sl[, attrib]
  sl_crs <- sf::st_crs(sl)
  if (!quiet) {
    message(paste0(Sys.time(), " constructing segments"))
  }
  c1 <- sf::st_coordinates(sl)
  sf::st_geometry(sl) <- NULL
  l1 <- c1[, 3] # Get which line each point is part of
  c1 <- c1[, 1:2]
  l1_start <- duplicated(l1) # find the break points between lines
  l1_start <- c(l1_start[2:length(l1)], FALSE)
  c2 <- c1[2:nrow(c1), 1:2] # Create new coords offset by one row
  c2 <- rbind(c2, c(NA, NA))
  c2[nrow(c1), ] <- c(NA, NA)
  c2[!l1_start, 1] <- NA
  c2[!l1_start, 2] <- NA
  c3 <- cbind(c1, c2) # make new matrix of start and end coords
  rm(c1, c2)
  c3 <- c3[!is.na(c3[, 3]), ]
  sl <- sl[l1[l1_start], , drop = FALSE] # repeate attributes
  rm(l1, l1_start)

  # if (!quiet) {
  #   message(paste0(Sys.time(), " transposing 'B to A' to 'A to B'"))
  # }
  attributes(c3)$dimnames <- NULL
  c3 <- t(apply(c3, MARGIN = 1, FUN = function(y) {
    if (y[1] != y[3]) {
      if (y[1] > y[3]) {
        c(y[3], y[4], y[1], y[2])
      } else {
        y
      }
    } else {
      if (y[2] > y[4]) {
        c(y[3], y[4], y[1], y[2])
      } else {
        y
      }
    }
  }))

  # if (!quiet) {
  #   message(paste0(Sys.time(), " removing duplicates"))
  # }
  sl <- cbind(c3, sl)
  rm(c3)

  sl <- dplyr::group_by_at(sl, c("1", "2", "3", "4"))
  sl <- dplyr::ungroup(dplyr::summarise_all(sl, .funs = sum))
  coords <- as.matrix(sl[, 1:4])
  sl <- sl[, attrib]

  # Make Geometry
  if (!quiet) {
    message(paste0(Sys.time(), " building geometry"))
  }
  sf::st_geometry(sl) <- sf::st_as_sfc(
    if (requireNamespace("pbapply", quietly = TRUE)) {
      pbapply::pblapply(1:nrow(coords), function(y) {
        sf::st_linestring(matrix(coords[y, ], ncol = 2, byrow = T))
      })
    } else {
      lapply(1:nrow(coords), function(y) {
        sf::st_linestring(matrix(coords[y, ], ncol = 2, byrow = T))
      })
    },
    crs = sl_crs
  )
  rm(coords)

  # Recombine into fewer lines
  if (simplify) {
    if (!quiet) {
      message(paste0(Sys.time(), " simplifying geometry"))
    }
    if (nrow(sl) > regionalise) {
      message(paste0("large data detected, using regionalisation, nrow = ", nrow(sl)))
      suppressWarnings(cents <- sf::st_centroid(sl))
      grid <- sf::st_make_grid(cents, what = "polygons")
      suppressWarnings(inter <- unlist(lapply(sf::st_intersects(cents, grid), `[[`, 1)))
      sl$grid <- inter
      rm(cents, grid, inter)
      # split into a list of df by grid
      sl <- dplyr::group_split(sl, grid)
      message(paste0(Sys.time(), " regionalisation complete, aggregating flows"))
      if (ncores > 1) {
        cl <- parallel::makeCluster(ncores)
        parallel::clusterExport(
          cl = cl,
          varlist = c("attrib"),
          envir = environment()
        )
        parallel::clusterEvalQ(cl, {
          library(sf)
          # library(dplyr)
        })
        overlined_simple <- if (requireNamespace("pbapply", quietly = TRUE)) {
          pbapply::pblapply(sl, function(y) {
            y <- dplyr::group_by_at(y, attrib)
            y <- dplyr::summarise(y, do_union = FALSE, .groups = 'drop')
          }, cl = cl)
        } else {
          lapply(sl, function(y) {
            y <- dplyr::group_by_at(y, attrib)
            y <- dplyr::summarise(y, do_union = FALSE, .groups = 'drop')
          })
        }


        parallel::stopCluster(cl)
        rm(cl)
      } else {
        overlined_simple <- if (requireNamespace("pbapply", quietly = TRUE)) {
          pbapply::pblapply(sl, function(y) {
            y <- dplyr::group_by_at(y, attrib)
            y <- dplyr::summarise(y, do_union = FALSE, .groups = 'drop')
          })
        } else {
          lapply(sl, function(y) {
            y <- dplyr::group_by_at(y, attrib)
            y <- dplyr::summarise(y, do_union = FALSE, .groups = 'drop')
          })
        }
      }
      rm(sl)
      overlined_simple <- data.table::rbindlist(overlined_simple)
      overlined_simple <- sf::st_sf(overlined_simple)
      overlined_simple <- overlined_simple[seq_len(nrow(overlined_simple)),]
    } else {
      if (!quiet) {
        message(paste0(Sys.time(), " aggregating flows"))
      }
      overlined_simple <- dplyr::group_by_at(sl, attrib)
      overlined_simple <- dplyr::summarise(overlined_simple, do_union = FALSE, .groups = 'drop')
      rm(sl)
    }

    overlined_simple <- as.data.frame(overlined_simple)
    overlined_simple <- sf::st_sf(overlined_simple)

    # Separate our the linestrings and the mulilinestrings
    if (!quiet) {
      message(paste0(Sys.time(), " rejoining segments into linestrings"))
    }
    overlined_simple <- sf::st_line_merge(overlined_simple)
    geom_types <- sf::st_geometry_type(overlined_simple)
    overlined_simple_l <- overlined_simple[geom_types == "LINESTRING", ]
    overlined_simple_ml <- overlined_simple[geom_types == "MULTILINESTRING", ]
    suppressWarnings(overlined_simple_ml <-
      sf::st_cast(
        sf::st_cast(overlined_simple_ml, "MULTILINESTRING"),
        "LINESTRING"
      ))

    return(rbind(overlined_simple_l, overlined_simple_ml))
  } else {
    return(sl)
  }
}


#' Convert series of overlapping lines into a route network
#'
#' This function takes overlapping `LINESTRING`s stored in an
#' `sf` object and returns a route network composed of non-overlapping
#' geometries and aggregated values.
#'
#' @param sl An `sf` `LINESTRING` object with overlapping elements
#' @inheritParams overline
#' @export
#' @examples
#' routes_fast_sf$value <- 1
#' sl <- routes_fast_sf[4:6, ]
#' attrib <- c("value", "length")
#' rnet <- overline_intersection(sl = sl, attrib)
#' plot(rnet, lwd = rnet$value)
#' # A larger example
#' sl <- routes_fast_sf[4:7, ]
#' rnet <- overline_intersection(sl = sl, attrib = c("value", "length"))
#' plot(rnet, lwd = rnet$value)
#' rnet_sf <- overline(routes_fast_sf[4:7, ], attrib = c("value", "length"), buff_dist = 10)
#' plot(rnet_sf, lwd = rnet_sf$value)
#'
#' # An even larger example (not shown, takes time to run)
#' # rnet = overline_intersection(routes_fast_sf, attrib = c("value", "length"))
#' # rnet_sf <- overline(routes_fast_sf, attrib = c("value", "length"), buff_dist = 10)
#' # plot(rnet$geometry, lwd = rnet$value * 2, col = "grey")
#' # plot(rnet_sf$geometry,  lwd = rnet_sf$value, add = TRUE)
overline_intersection <- function(sl, attrib, fun = sum, na.zero = FALSE, buff_dist = 0) {
  sl <- sl[attrib]
  sli <- sf::st_intersection(sl)

  # check it's all in there:
  # sli_union = sf::st_union(sli)
  # plot(sli_union, lwd = 9)
  # plot(sl$geometry, add = T, col = "red")
  # sl_difference = sf::st_difference(sl, sli)

  gtypes <- sf::st_geometry_type(sli)
  sli_lines <- sli[gtypes == "LINESTRING", ]
  sli_mlines <- sli[gtypes == "MULTILINESTRING", ]

  if (any(gtypes == "GEOMETRYCOLLECTION")) {
    sli_collections <- sli[gtypes == "GEOMETRYCOLLECTION", ]
    sli_clines <- sf::st_collection_extract(sli_collections, "LINESTRING")
    sli_lines <- rbind(sli_lines, sli_clines)
  }

  # # Test plots:
  # plot(sli_lines$geometry, lwd = sli_lines$n.overlaps * 2, col = "grey")
  # plot(sli_mlines$geometry, add = TRUE, lwd = sli_mlines$n.overlaps)
  # plot(sl$geometry, col = "red", add = TRUE)

  # # removes many lines!
  l_mlines <- lapply(sli_mlines$geometry, sf::st_line_merge)
  l_mlines_sfc <- sf::st_sfc(l_mlines, crs = sf::st_crs(sl))
  # plot(l_mlines_sfc)

  l_mlines_data <- lapply(attrib, function(a) {
    vapply(sli_mlines$origins, function(i) fun(sl[[a]][i]), FUN.VALUE = numeric(1))
  })
  names(l_mlines_data) <- attrib
  mlines <- sf::st_sf(l_mlines_data, geometry = l_mlines_sfc)
  slines <- sli_lines[attrib]
  rbind(mlines, slines)
}
